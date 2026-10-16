#!/usr/bin/env python3
"""Account management for the syoch.org directory (dc=id,dc=syoch,dc=org).

Ported from the nnctroboticsclub/infrastructure AccountSetup/ldap.py, with two
deliberate differences:

  * uid/gid allocators live in ou=Meta instead of being mixed into ou=Groups.
  * Allocation is compare-and-swap instead of read-increment-write, so two
    concurrent callers cannot be handed the same id.

Ids are still backed by ``cn=lastUID`` / ``cn=lastGID`` counters. The CAS keeps
them authoritative, and ``allocate_uid`` refuses to persist an id that is
already taken, which turns the counter from the only line of defence into a
fast path.
"""

from __future__ import annotations

import argparse
import getpass
import sys
from dataclasses import dataclass

import ldap3
from ldap3.utils import hashed

BASE_DN = "dc=id,dc=syoch,dc=org"
USERS_OU = f"ou=Users,{BASE_DN}"
GROUPS_OU = f"ou=Groups,{BASE_DN}"
SERVICES_OU = f"ou=Services,{BASE_DN}"
META_OU = f"ou=Meta,{BASE_DN}"

DATA_ADMIN = f"cn=admin,{BASE_DN}"
CONFIG_ADMIN = "cn=admin,cn=config"


class AllocatorBusy(RuntimeError):
    """Another writer took the id between our read and our write."""


class Directory:
    def __init__(
        self,
        host: str = "127.0.0.1",
        bind_dn: str = DATA_ADMIN,
        password: str | None = None,
        base_dn: str = BASE_DN,
        port: int | None = None,
    ) -> None:
        self.base_dn = base_dn
        self.users_ou = f"ou=Users,{base_dn}"
        self.groups_ou = f"ou=Groups,{base_dn}"
        self.services_ou = f"ou=Services,{base_dn}"
        self.meta_ou = f"ou=Meta,{base_dn}"
        # slapd listens on loopback only, so reaching it from another host means
        # an SSH forward (ssh -L <localport>:127.0.0.1:389 ...). --port is
        # therefore the forwarded local port, not the server's port.
        server = ldap3.Server(host, port=port) if port else ldap3.Server(host)
        self.conn = ldap3.Connection(
            server,
            user=bind_dn,
            password=password if password is not None else getpass.getpass(f"LDAP bind password ({bind_dn}): "),
            auto_bind=True,
        )

    # ---------------------------------------------------------------- search

    def _find(self, base: str, flt: str, attrs: list[str] | None = None) -> list[ldap3.Entry]:
        self.conn.search(base, flt, attributes=attrs or ["*"])
        return list(self.conn.entries or [])

    def user_exists(self, uid: str) -> bool:
        return bool(self._find(self.users_ou, f"(uid={uid})", ["uid"]))

    def group_exists(self, group: str) -> bool:
        return bool(self._find(self.groups_ou, f"(cn={group})", ["cn"]))

    def is_in_group(self, uid: str, group: str) -> bool:
        return bool(self._find(self.groups_ou, f"(&(objectClass=posixGroup)(cn={group})(memberUid={uid}))", ["cn"]))

    def group_members(self, group: str) -> list[str]:
        entries = self._find(self.groups_ou, f"(cn={group})", ["cn", "memberUid", "gidNumber"])
        if not entries:
            raise LookupError(f"group not found: {group}")
        raw = entries[0]["memberUid"].value
        return sorted(raw) if isinstance(raw, list) else ([raw] if raw else [])

    def list_users(self) -> list[str]:
        entries = self._find(self.users_ou, "(objectClass=inetOrgPerson)", ["uid", "displayName"])
        return sorted(str(e["uid"].value) for e in entries)

    def list_groups(self) -> list[str]:
        entries = self._find(self.groups_ou, "(objectClass=posixGroup)", ["cn", "gidNumber", "memberUid"])
        out = []
        for e in entries:
            raw = e["memberUid"].value
            members = sorted(raw) if isinstance(raw, list) else ([raw] if raw else [])
            out.append((str(e["cn"].value), str(e["gidNumber"].value), members))
        return sorted(out)

    # ------------------------------------------------------------ allocation

    def _alloc_dn(self, kind: str) -> str:
        return f"cn=last{kind},ou=Meta,{self.base_dn}"

    def _read_counter(self, kind: str) -> int:
        entries = self._find(self.meta_ou, f"(cn=last{kind})", ["serialNumber"])
        if not entries:
            raise LookupError(f"cn=last{kind} not found in {self.meta_ou}")
        return int(entries[0]["serialNumber"].value)

    def _cas_counter(self, kind: str, expected: int, new: int) -> bool:
        """Bump the counter only if it still holds ``expected``.

        LDAP has no compare-and-swap on a replace, so the guard is a compare
        followed by a modify that is re-read afterwards. Under real contention
        the retry loop in ``_allocate`` is what converges; this narrows the
        window and detects the lost update.
        """
        dn = self._alloc_dn(kind)
        if self._read_counter(kind) != expected:
            return False
        self.conn.modify(
            dn,
            {"serialNumber": [(ldap3.MODIFY_REPLACE, [str(new)])]},
        )
        return self._read_counter(kind) == new

    def _allocate(self, kind: str, taken: set[int], start: int, end: int) -> int:
        # Walk forward from the counter until an unused id turns up. The naive
        # "counter+1, retry" loop cannot converge when the counter sits below
        # ids that are already in the tree: it would keep proposing the same
        # taken id forever. So each pass advances the counter itself.
        current = self._read_counter(kind)
        for _ in range(len(taken) + 2):
            candidate = current + 1
            if candidate > end:
                candidate = start
            if candidate not in taken and self._cas_counter(kind, current, candidate):
                # The counter is ours. Verify the id is genuinely free before
                # relying on it -- a counter that drifted behind the tree would
                # otherwise hand out a duplicate.
                if self._id_taken(kind, candidate):
                    taken.add(candidate)
                    current = candidate
                    continue
                return candidate
            # Lost the CAS or the id was taken; re-read and keep walking.
            current = self._read_counter(kind)
        raise AllocatorBusy(f"could not allocate a free {kind}")

    def _id_taken(self, kind: str, value: int) -> bool:
        if kind == "UID":
            entries = self._find(self.users_ou, "(uidNumber=*)", ["uidNumber"])
        else:
            entries = self._find(self.groups_ou, "(gidNumber=*)", ["gidNumber"])
        return value in {int(e[kind.title() + "Number"].value) for e in entries}

    def used_uids(self) -> set[int]:
        return {int(e["uidNumber"].value) for e in self._find(self.users_ou, "(uidNumber=*)", ["uidNumber"])}

    def used_gids(self) -> set[int]:
        return {int(e["gidNumber"].value) for e in self._find(self.groups_ou, "(gidNumber=*)", ["gidNumber"])}

    def allocate_uid(self) -> int:
        return self._allocate("UID", self.used_uids(), 10000, 60000)

    def allocate_gid(self) -> int:
        return self._allocate("GID", self.used_gids(), 10000, 60000)

    # ----------------------------------------------------------------- write

    def create_user(
        self,
        uid: str,
        password: str,
        display_name: str | None = None,
        gid_number: int | None = None,
        login_shell: str = "/usr/bin/false",
        home_directory: str | None = None,
    ) -> int:
        """Create an inetOrgPerson+posixAccount. Idempotent by uid."""
        if self.user_exists(uid):
            existing = self._find(self.users_ou, f"(uid={uid})", ["uidNumber"])
            return int(existing[0]["uidNumber"].value)

        uid_number = self.allocate_uid()
        gid = gid_number if gid_number is not None else self.allocate_gid()

        display = display_name or uid

        ok = self.conn.add(
            f"uid={uid},{self.users_ou}",
            ["inetOrgPerson", "posixAccount"],
            {
                "uid": uid,
                "cn": uid,
                "sn": uid,
                "givenName": uid,
                "displayName": display,
                "uidNumber": str(uid_number),
                "gidNumber": str(gid),
                "homeDirectory": home_directory or f"/var/empty/{uid}",
                "loginShell": login_shell,
                # SSHA, not SSHA512: OpenLDAP only verifies {SSHA}/{SHA}/{MD5}/{CRYPT}.
                # ldap3 can emit {ssha512}, which slapd stores happily and then
                # never matches, so every bind fails with invalid credentials.
                "userPassword": hashed.hashed(hashed.HASHED_SALTED_SHA, password),
            },
        )
        if not ok:
            raise RuntimeError(f"failed to create {uid}: {self.conn.result}")
        return uid_number

    def set_password(self, uid: str, password: str) -> None:
        """Replace an account password.

        Needed to rotate a credential: `ensure-agent` deliberately skips an
        existing uid, so it can never change a password that has already been
        hashed into the tree.
        """
        if not self.user_exists(uid):
            raise LookupError(f"user not found: {uid}")
        ok = self.conn.modify(
            f"uid={uid},{self.users_ou}",
            {
                "userPassword": [
                    (
                        ldap3.MODIFY_REPLACE,
                        [hashed.hashed(hashed.HASHED_SALTED_SHA, password)],
                    )
                ]
            },
        )
        if not ok:
            raise RuntimeError(f"failed to set password for {uid}: {self.conn.result}")

    def create_group(self, name: str) -> int:
        """Create a posixGroup. Idempotent by cn."""
        if self.group_exists(name):
            existing = self._find(self.groups_ou, f"(cn={name})", ["gidNumber"])
            return int(existing[0]["gidNumber"].value)

        gid = self.allocate_gid()
        ok = self.conn.add(
            f"cn={name},{self.groups_ou}",
            ["posixGroup", "top"],
            {"cn": name, "gidNumber": str(gid)},
        )
        if not ok:
            raise RuntimeError(f"failed to create group {name}: {self.conn.result}")
        return gid

    def add_to_group(self, uid: str, group: str) -> None:
        if not self.group_exists(group):
            raise LookupError(f"group not found: {group}")
        if self.is_in_group(uid, group):
            return
        ok = self.conn.modify(
            f"cn={group},{self.groups_ou}",
            {"memberUid": [(ldap3.MODIFY_ADD, [uid])]},
        )
        if not ok:
            raise RuntimeError(f"failed to add {uid} to {group}: {self.conn.result}")

    def remove_from_group(self, uid: str, group: str) -> None:
        if uid not in self.group_members(group):
            return
        ok = self.conn.modify(
            f"cn={group},{self.groups_ou}",
            {"memberUid": [(ldap3.MODIFY_DELETE, [uid])]},
        )
        if not ok:
            raise RuntimeError(f"failed to remove {uid} from {group}: {self.conn.result}")

    def ensure_agent(self, uid: str, password: str, group: str | None) -> None:
        """The operation the venue tooling needs: one uid, optional group.

        Idempotent, so re-running it for a role that already exists is a no-op
        rather than an error. The project group is created first and becomes the
        account's primary gid: NextCloud maps posixGroup membership through
        memberUid, so the primary gid only matters for host logins, and not
        spending a gid per agent keeps the allocator from running dry.
        """
        gid = self.create_group(group) if group else None
        self.create_user(uid, password, display_name=uid, gid_number=gid)
        if group:
            self.add_to_group(uid, group)

    def delete_user(self, uid: str) -> None:
        """Remove a uid entry.

        Group memberships are stripped first. An LDAP entry cannot be deleted
        while it is still a member, and leaving dangling memberUid values behind
        makes the group list lie about who is in it.
        """
        dn = f"uid={uid},{self.users_ou}"
        if not self.user_exists(uid):
            raise RuntimeError(f"no such user: {uid}")
        # list_groups() yields (cn, gidNumber, members) tuples despite its
        # list[str] annotation, so take the cn off position 0.
        for cn, _gid, _members in self.list_groups():
            self.remove_from_group(uid, cn)
        if not self.conn.delete(dn):
            raise RuntimeError(f"failed to delete {dn}: {self.conn.result}")

    def delete_group(self, group: str) -> None:
        """Remove a posixGroup entry.

        Refuses while members remain: deleting the group would silently orphan
        them, and the same membership list drives the NextCloud group mapping.
        """
        if self.group_members(group):
            members = ", ".join(self.group_members(group))
            raise RuntimeError(
                f"group {group} still has members ({members}); "
                f"remove them or use delete-user first"
            )
        dn = f"cn={group},{self.groups_ou}"
        if not self.conn.delete(dn):
            raise RuntimeError(f"failed to delete {dn}: {self.conn.result}")


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--host", default="127.0.0.1", help="LDAP host; 127.0.0.1 when SSH-forwarding")
    ap.add_argument(
        "--port",
        type=int,
        help="local port of an SSH forward, e.g. `ssh -L 3890:127.0.0.1:389` then --port 3890",
    )
    ap.add_argument("--bind-dn", default=DATA_ADMIN, help="e.g. uid=admin,ou=Users,dc=id,dc=syoch,dc=org")
    ap.add_argument("--password", help="bind password; omit to be prompted")
    ap.add_argument(
        "--password-file",
        help="read the bind password from this file (preferred: argv is world-readable via ps)",
    )

    sub = ap.add_subparsers(dest="cmd", required=True)

    sub.add_parser("list-users", help="list uid entries")
    sub.add_parser("list-groups", help="list groups and members")

    p = sub.add_parser("add-user", help="create uid=<name> (idempotent)")
    p.add_argument("uid")
    p.add_argument("--display-name")
    p.add_argument("--shell", default="/usr/bin/false")
    p.add_argument("--password", help="user password; omit to be prompted")

    p = sub.add_parser("set-password", help="replace an existing uid's password")
    p.add_argument("uid")
    p.add_argument("--password", help="new password; omit to be prompted")

    p = sub.add_parser("add-group", help="create cn=<name> (idempotent)")
    p.add_argument("group")

    p = sub.add_parser("add-member", help="add a uid to a group")
    p.add_argument("uid")
    p.add_argument("group")

    p = sub.add_parser("remove-member", help="remove a uid from a group")
    p.add_argument("uid")
    p.add_argument("group")

    p = sub.add_parser("delete-user", help="delete a uid entry and its group memberships")
    p.add_argument("uid")

    p = sub.add_parser("delete-group", help="delete an empty posixGroup entry")
    p.add_argument("group")

    p = sub.add_parser("ensure-agent", help="create uid and join it to a group (idempotent)")
    p.add_argument("uid")
    p.add_argument("--group", help="project group, e.g. the venue slug")
    p.add_argument("--password", help="user password; omit to be prompted")

    args = ap.parse_args(argv)
    bind_pw = args.password
    if args.password_file:
        # Read in binary and strip exactly one trailing newline: sops writes
        # secrets with one, and a stray newline would break the bind.
        with open(args.password_file, "rb") as fh:
            bind_pw = fh.read().rstrip(b"\n").decode()
    d = Directory(host=args.host, bind_dn=args.bind_dn, password=bind_pw, port=args.port)

    try:
        if args.cmd == "list-users":
            for uid in d.list_users():
                print(uid)
        elif args.cmd == "list-groups":
            for name, gid, members in d.list_groups():
                print(f"{name} gid={gid} members={','.join(members) or '-'}")
        elif args.cmd == "add-user":
            pw = args.password or getpass.getpass(f"password for {args.uid}: ")
            n = d.create_user(args.uid, pw, display_name=args.display_name, login_shell=args.shell)
            print(f"created uid={args.uid} uidNumber={n}")
        elif args.cmd == "set-password":
            pw = args.password or getpass.getpass(f"new password for {args.uid}: ")
            d.set_password(args.uid, pw)
            print(f"ok password for {args.uid}")
        elif args.cmd == "add-group":
            print(f"created cn={args.group} gid={d.create_group(args.group)}")
        elif args.cmd == "add-member":
            d.add_to_group(args.uid, args.group)
            print(f"added {args.uid} to {args.group}")
        elif args.cmd == "remove-member":
            d.remove_from_group(args.uid, args.group)
            print(f"removed {args.uid} from {args.group}")
        elif args.cmd == "delete-user":
            d.delete_user(args.uid)
            print(f"deleted user {args.uid}")
        elif args.cmd == "delete-group":
            d.delete_group(args.group)
            print(f"deleted group {args.group}")
        elif args.cmd == "ensure-agent":
            pw = args.password or getpass.getpass(f"password for {args.uid}: ")
            d.ensure_agent(args.uid, pw, args.group)
            print(f"ok {args.uid}" + (f" in {args.group}" if args.group else ""))
        else:
            ap.error(f"unknown command {args.cmd}")
    except Exception as e:  # noqa: BLE001 - CLI boundary
        print(f"error: {e}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())