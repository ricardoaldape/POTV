"""Bounded private NOVA catalog size shared by the sync and gateway.

A 12 MiB limit could discard the entire subscriber TV catalog as the
progressive movie/series shelves approach 5,000 items each. Keep a hard
upper bound for the 384 MiB gateway cgroup and fail closed before replacing
the last good snapshot if that bound is exceeded.
"""
MAX_NOVA_SNAPSHOT_BYTES = 24 * 1024 * 1024
