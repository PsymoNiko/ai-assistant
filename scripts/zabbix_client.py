"""Zabbix API client using requests

Implements a small, reusable JSON-RPC client for the Zabbix API v5/6/7.
See: https://www.zabbix.com/documentation/7.4/en/manual/api#performing-requests

Usage:
    from zabbix_client import ZabbixAPI
    api = ZabbixAPI(url="https://zabbix.example.com", user="Admin", password="zabbix")
    api.login()
    hosts = api.host_get(output=["hostid","host","name"]) 
    print(hosts)
    api.logout()

This file is intended to be placed in scripts/ in the repository.
"""

from typing import Any, Dict, Optional, List
import requests


class ZabbixAPIError(Exception):
    """Raised when the Zabbix API returns an error."""


class ZabbixAPI:
    """Simple Zabbix JSON-RPC client using requests.Session.

    The client keeps a session and an `auth` token returned by `user.login`.
    Methods are convenience wrappers around common API calls.
    """

    def __init__(self, url: str, user: Optional[str] = None, password: Optional[str] = None, timeout: int = 30):
        # Ensure we post to api_jsonrpc.php
        self.api_url = url.rstrip("/") + "/api_jsonrpc.php"
        self.user = user
        self.password = password
        self.timeout = timeout
        self.session = requests.Session()
        self._auth: Optional[str] = None
        self._id = 0

    def _next_id(self) -> int:
        self._id += 1
        return self._id

    def request(self, method: str, params: Optional[Dict[str, Any]] = None, auth_required: bool = True) -> Any:
        """Perform a JSON-RPC request to the Zabbix API.

        Raises ZabbixAPIError on protocol error or API error.
        Returns the `result` field on success.
        """
        payload = {
            "jsonrpc": "2.0",
            "method": method,
            "params": params or {},
            "id": self._next_id(),
        }

        if auth_required:
            if not self._auth:
                raise ZabbixAPIError("Authentication required: call login() first")
            payload["auth"] = self._auth
        else:
            payload["auth"] = None

        try:
            resp = self.session.post(self.api_url, json=payload, timeout=self.timeout)
        except requests.RequestException as exc:
            raise ZabbixAPIError(f"HTTP request failed: {exc}") from exc

        if resp.status_code != 200:
            raise ZabbixAPIError(f"Unexpected HTTP status: {resp.status_code}: {resp.text}")

        try:
            data = resp.json()
        except ValueError as exc:
            raise ZabbixAPIError(f"Invalid JSON response: {exc}") from exc

        if "error" in data:
            err = data["error"]
            raise ZabbixAPIError(f"Zabbix API error {err.get('code')}: {err.get('message')} - {err.get('data')}")

        return data.get("result")

    def login(self) -> str:
        """Authenticate and store the auth token.

        Requires `user` and `password` provided at __init__ or externally.
        Returns the auth token.
        """
        if not self.user or not self.password:
            raise ZabbixAPIError("user and password are required to login")

        result = self.request("user.login", {"user": self.user, "password": self.password}, auth_required=False)
        self._auth = result
        return self._auth

    def logout(self) -> bool:
        """Invalidate the auth token on the server and clear local auth."""
        try:
            result = self.request("user.logout", {}, auth_required=True)
        finally:
            # Always clear local auth regardless of server response
            self._auth = None
        return bool(result)

    # Convenience wrappers
    def host_get(self, output: Optional[List[str]] = None, hostids: Optional[List[str]] = None, search: Optional[Dict[str, str]] = None, limit: Optional[int] = None) -> Any:
        params: Dict[str, Any] = {}
        if output is not None:
            params["output"] = output
        if hostids is not None:
            params["hostids"] = hostids
        if search is not None:
            params["search"] = search
        if limit is not None:
            params["limit"] = limit
        return self.request("host.get", params)

    def host_create(self, host: str, interfaces: List[Dict[str, Any]], groups: List[Dict[str, Any]], templates: Optional[List[Dict[str, Any]]] = None) -> Any:
        params: Dict[str, Any] = {"host": host, "interfaces": interfaces, "groups": groups}
        if templates:
            params["templates"] = templates
        return self.request("host.create", params)

    def item_get(self, output: Optional[List[str]] = None, hostids: Optional[List[str]] = None, search: Optional[Dict[str, str]] = None) -> Any:
        params: Dict[str, Any] = {}
        if output is not None:
            params["output"] = output
        if hostids is not None:
            params["hostids"] = hostids
        if search is not None:
            params["search"] = search
        return self.request("item.get", params)

    def trigger_get(self, output: Optional[List[str]] = None, hostids: Optional[List[str]] = None, filter: Optional[Dict[str, Any]] = None) -> Any:
        params: Dict[str, Any] = {}
        if output is not None:
            params["output"] = output
        if hostids is not None:
            params["hostids"] = hostids
        if filter is not None:
            params["filter"] = filter
        return self.request("trigger.get", params)


# If the module is executed directly, show a tiny interactive example.
if __name__ == "__main__":
    import os
    import pprint

    ZABBIX_URL = os.environ.get("ZABBIX_URL")
    ZABBIX_USER = os.environ.get("ZABBIX_USER")
    ZABBIX_PASSWORD = os.environ.get("ZABBIX_PASSWORD")

    if not (ZABBIX_URL and ZABBIX_USER and ZABBIX_PASSWORD):
        print("Set ZABBIX_URL, ZABBIX_USER and ZABBIX_PASSWORD environment variables to run this example")
    else:
        api = ZabbixAPI(ZABBIX_URL, user=ZABBIX_USER, password=ZABBIX_PASSWORD)
        try:
            api.login()
            hosts = api.host_get(output=["hostid", "host"], limit=10)
            pprint.pprint(hosts)
        except ZabbixAPIError as e:
            print("Error:", e)
        finally:
            api.logout()
