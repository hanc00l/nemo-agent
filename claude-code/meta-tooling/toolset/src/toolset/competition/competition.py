"""
Competition - 第二届腾讯云黑客松智能渗透挑战赛 API

文档: 第二届腾讯云黑客松智能渗透挑战赛API文档.md
"""
import os
import time
import requests
from typing import Annotated, List, Dict, Any, Optional
from dataclasses import dataclass, field
from core import tool, toolset, namespace

namespace()

DEFAULT_BASE_URL = "http://host.docker.internal"


@dataclass
class ChallengeInfo:
    code: str
    title: str
    difficulty: str
    level: int
    total_score: int
    total_got_score: int
    flag_count: int
    flag_got_count: int
    hint_viewed: bool
    instance_status: str
    entrypoint: List[str] = field(default_factory=list)

    @property
    def is_solved(self) -> bool:
        return self.flag_got_count >= self.flag_count


@toolset()
class Competition:
    """腾讯云黑客松智能渗透挑战赛 API。详见第二届腾讯云黑客松智能渗透挑战赛API文档.md"""

    def __init__(self, base_url: str = None, agent_token: str = None):
        self.base_url = (base_url or os.getenv("COMPETITION_API_URL", DEFAULT_BASE_URL)).rstrip("/")
        self.agent_token = agent_token or os.getenv("AGENT_TOKEN", "")
        if not self.agent_token:
            self._log("WARNING: AGENT_TOKEN 为空！所有 API 调用将返回 401 认证失败", "warn")
        self.session = requests.Session()
        self.session.headers.update({
            "Content-Type": "application/json",
            "Accept": "application/json",
            "Agent-Token": self.agent_token,
        })
        self._cache: Optional[Dict[str, ChallengeInfo]] = None
        self._cache_time: float = 0
        self._last_request_time: float = 0

    def _log(self, msg: str, level: str = "info"):
        print(f"[{time.strftime('%H:%M:%S')}] [{level.upper()}] {msg}")

    def _rate_limit(self):
        """频率控制：确保请求间隔 >= 0.5s（API 限制 3次/秒）"""
        elapsed = time.time() - self._last_request_time
        if elapsed < 0.5:
            time.sleep(0.5 - elapsed)
        self._last_request_time = time.time()

    def _request(self, method: str, path: str, **kwargs) -> Dict[str, Any]:
        """统一请求方法，处理频率限制和错误（含 429 重试）"""
        self._rate_limit()
        url = f"{self.base_url}/api{path}"

        # 429 重试（最多 3 次）
        max_retries = 3
        for attempt in range(max_retries):
            resp = self.session.request(method, url, timeout=30, **kwargs)

            if resp.status_code == 429:
                wait_time = min(int(resp.headers.get("Retry-After", "1")), 2)
                self._log(f"429 频率限制，等待 {wait_time}s (第 {attempt + 1}/{max_retries} 次)", "warn")
                time.sleep(wait_time)
                continue
            break
        else:
            raise RuntimeError(f"API 429 重试耗尽: {method} {path}")

        resp.raise_for_status()
        data = resp.json()

        if data.get("code") != 0:
            raise RuntimeError(f"API 错误 (code={data.get('code')}): {data.get('message', 'unknown')}")

        return data.get("data", data)

    @tool()
    def get_challenges(self, refresh: Annotated[bool, "强制刷新缓存"] = False) -> List[Dict[str, Any]]:
        """获取赛题列表 (缓存60秒)。返回赛题数组，含 code/title/difficulty/level/score/flag 等信息。"""
        if not refresh and self._cache and (time.time() - self._cache_time) < 60:
            return [vars(c) for c in self._cache.values()]

        data = self._request("GET", "/challenges")
        challenges = data.get("challenges", []) if isinstance(data, dict) else []
        current_level = data.get("current_level", 0) if isinstance(data, dict) else 0

        self._cache = {}
        result = []
        for c in challenges:
            info = ChallengeInfo(
                code=c.get("code", ""),
                title=c.get("title", ""),
                difficulty=c.get("difficulty", "unknown"),
                level=c.get("level", 0),
                total_score=c.get("total_score", 0),
                total_got_score=c.get("total_got_score", 0),
                flag_count=c.get("flag_count", 0),
                flag_got_count=c.get("flag_got_count", 0),
                hint_viewed=c.get("hint_viewed", False),
                instance_status=c.get("instance_status", "stopped"),
                entrypoint=c.get("entrypoint") or [],
            )
            self._cache[info.code] = info
            result.append(vars(info))

        self._cache_time = time.time()
        self._log(f"获取 {len(result)} 个赛题 (当前关卡: {current_level})")
        return result

    @tool()
    def start_challenge(self, code: Annotated[str, "赛题唯一标识"]) -> Dict[str, Any]:
        """启动赛题实例。返回入口地址列表。每队同时最多运行 3 个赛题实例。"""
        data = self._request("POST", "/start_challenge", json={"code": code})

        # 已全部完成的情况
        if isinstance(data, dict) and data.get("already_completed"):
            self._log(f"赛题 {code} 已全部完成", "warn")
            return {"already_completed": True, "entrypoint": []}

        entrypoint = data if isinstance(data, list) else []
        if self._cache and code in self._cache:
            self._cache[code].instance_status = "running"
            self._cache[code].entrypoint = entrypoint

        self._log(f"赛题 {code} 已启动，入口: {entrypoint}")
        return {"entrypoint": entrypoint}

    @tool()
    def stop_challenge(self, code: Annotated[str, "赛题唯一标识"]) -> Dict[str, Any]:
        """停止赛题实例，释放资源。"""
        self._request("POST", "/stop_challenge", json={"code": code})

        if self._cache and code in self._cache:
            self._cache[code].instance_status = "stopped"
            self._cache[code].entrypoint = []

        self._log(f"赛题 {code} 已停止")
        return {"stopped": True}

    @tool()
    def submit_answer(
        self,
        code: Annotated[str, "赛题唯一标识"],
        flag: Annotated[str, "FLAG 字符串 (如 flag{xxx})"],
    ) -> Dict[str, Any]:
        """提交 FLAG 答案。每个 FLAG 只能得分一次。赛题实例需处于运行状态。"""
        data = self._request("POST", "/submit", json={"code": code, "flag": flag})

        correct = data.get("correct", False)
        flag_count = data.get("flag_count", 0)
        flag_got_count = data.get("flag_got_count", 0)
        message = data.get("message", "")

        result = {
            "correct": correct,
            "flag_count": flag_count,
            "flag_got_count": flag_got_count,
            "message": message,
            "is_solved": flag_got_count >= flag_count,
        }

        if correct:
            self._log(f"正确! {message}")
            if self._cache and code in self._cache:
                self._cache[code].flag_got_count = flag_got_count
                self._cache[code].total_got_score = flag_got_count * (self._cache[code].total_score // max(flag_count, 1))
        else:
            self._log(f"错误: {message}", "warn")

        return result

    @tool()
    def get_hint(self, code: Annotated[str, "赛题唯一标识"]) -> Dict[str, Any]:
        """查看赛题提示 (首次查看扣减 10% 奖励分数)。只能查看已启动且未全部答对的赛题。"""
        data = self._request("POST", "/hint", json={"code": code})

        hint_content = data.get("hint_content", "")
        self._log(f"赛题 {code} 提示: {hint_content}")

        if self._cache and code in self._cache:
            self._cache[code].hint_viewed = True

        return {"hint_content": hint_content, "code": code}

    @tool()
    def get_unsolved_challenges(self, refresh: Annotated[bool, "强制刷新"] = False) -> List[Dict[str, Any]]:
        """获取未完成的赛题 (flag_got_count < flag_count)。"""
        return [c for c in self.get_challenges(refresh) if c.get("flag_got_count", 0) < c.get("flag_count", 1)]

    @tool()
    def get_solved_challenges(self, refresh: Annotated[bool, "强制刷新"] = False) -> List[Dict[str, Any]]:
        """获取已完成的赛题 (flag_got_count >= flag_count)。"""
        return [c for c in self.get_challenges(refresh) if c.get("flag_got_count", 0) >= c.get("flag_count", 1)]

    @tool()
    def get_target_url(
        self,
        code: Annotated[str, "赛题唯一标识"],
        refresh: Annotated[bool, "强制刷新"] = False
    ) -> Optional[str]:
        """获取赛题目标 URL (http://ip:port)。需要赛题实例处于运行状态。"""
        for c in self.get_challenges(refresh):
            if c.get("code") == code:
                entrypoint = c.get("entrypoint") or []
                if entrypoint:
                    addr = entrypoint[0]
                    if not addr.startswith("http"):
                        addr = f"http://{addr}"
                    return addr
        return None
