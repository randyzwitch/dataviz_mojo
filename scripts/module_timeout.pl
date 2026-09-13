#!/usr/bin/env perl
# A wall-clock limit for one command, in the perl every macOS ships.
#
# `timeout(1)` is GNU coreutils. macOS has neither it nor Homebrew's
# `gtimeout` unless somebody installed them, so half the CI matrix ran
# every module unguarded (#543) and so does every contributor on a Mac.
# perl is the one interpreter both platforms are guaranteed to have, and
# `alarm` is the one timer that needs nothing from CPAN.
#
# Usage: module_timeout.pl <limit_seconds> <grace_seconds> <command> [args...]
#
# Exit codes match `timeout(1)` so the caller does not have to know which
# guard fired: 124 on a timeout, 128 + N when the command died on signal
# N (which is what makes a toolchain SIGSEGV show up as 139), and the
# command's own code otherwise.
#
# The obvious version of this is a one-liner -- set an alarm, exec the
# command, let SIGALRM kill the process -- and it is wrong twice.
#
# First, exec replaces this process, so there is nobody left to kill
# anything but itself. A command that forks leaves its children holding
# the output pipe open, and the caller's command substitution blocks on
# that pipe until they finish, which is exactly the wedge the limit
# exists to break. It reports the timeout on schedule and then hangs for
# the full duration anyway. `timeout(1)` avoids this by putting the
# child in its own process group and killing the group, so this forks
# and does the same.
#
# Second, a missing interpreter has to be loud. `perl -e` with no perl
# is "command not found", which a shell reports as 127 -- but only if
# the caller looks. run_parallel.sh probes with `command -v perl` before
# choosing this guard, so the absent case picks the unguarded path and
# says so, rather than silently passing everything.
use strict;
use warnings;
use POSIX qw(:errno_h);

my $limit = shift @ARGV;
my $grace = shift @ARGV;
die "usage: module_timeout.pl <limit> <grace> <command> [args...]\n"
    unless defined $limit && defined $grace && @ARGV;

my $pid = fork();
exit 127 unless defined $pid;
if ($pid == 0) {
    # The child leads its own process group, so killing -$pid reaches
    # anything it spawned. Without this the kill reaches the command and
    # not its children, which is the whole point.
    setpgrp(0, 0);
    exec { $ARGV[0] } @ARGV;
    exit 127;
}

my $fired = 0;
$SIG{ALRM} = sub {
    if ($fired) {
        kill 'KILL', -$pid;
        return;
    }
    # TERM first, then KILL after the grace, which is what the existing
    # Linux path asks `timeout` for with --kill-after. A process parked
    # on a futex will not answer either, but one merely slow gets the
    # chance to leave its output behind.
    $fired = 1;
    kill 'TERM', -$pid;
    alarm $grace;
};
alarm $limit;

# waitpid returns -1/EINTR when the alarm lands, which is not the child
# exiting; keep waiting until it actually is.
my $reaped;
do {
    $reaped = waitpid($pid, 0);
} while ($reaped == -1 && $! == EINTR);
my $status = $?;
alarm 0;

exit 124 if $fired;
exit 128 + ($status & 127) if ($status & 127);
exit $status >> 8;
