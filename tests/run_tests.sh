#!/usr/bin/env bash
# CSC 139 - Assignment 2 self-check.
# These are the same checks the grader relies on. When all twelve pass, this
# script prints the completion code you need for the Canvas quiz.
#
# Every run of your program is wrapped in a 20-second timeout, so a runall
# that hangs (or never stops creating processes) fails a check instead of
# freezing your codespace.

set -u

BIN=./runall
TMP=tests/tmp
H=tests/bin
COMPLETION_CODE="CSC139-A2-5FD81EE7"
pass=0
fail=0

ok()  { printf '  \033[32mPASS\033[0m  %s\n' "$1"; pass=$((pass+1)); }
bad() { printf '  \033[31mFAIL\033[0m  %s\n' "$1"; fail=$((fail+1)); }
why() { printf '        %s\n' "$@"; }

if [ "$(uname -s)" != "Linux" ]; then
  echo "These checks must be run on Linux. Open your codespace."
  exit 1
fi

if [ ! -x "$BIN" ] || [ ! -x "$H/probe" ]; then
  echo "runall not built. Run: make"
  exit 1
fi

rm -rf "$TMP"; mkdir -p "$TMP"

# run_ra ARGS... : runs ./runall, stdout -> $TMP/out, stderr -> $TMP/err, rc -> $rc
run_ra() {
  timeout 20 "$BIN" "$@" > "$TMP/out" 2> "$TMP/err"
  rc=$?
  if [ $rc -eq 124 ]; then
    timed_out=1
  else
    timed_out=0
  fi
}

# has REGEX : does runall's stdout contain a line matching REGEX?
has() { grep -Eq -- "$1" "$TMP/out"; }

# line_of REGEX : line number of the first match in stdout (0 if none)
line_of() { local n; n=$(grep -En -- "$1" "$TMP/out" | head -1 | cut -d: -f1); echo "${n:-0}"; }

show_out() {
  if [ "$timed_out" -eq 1 ]; then why "(runall was still running after 20 seconds and was stopped)"; fi
  if [ -s "$TMP/out" ]; then
    why "your program printed:"
    head -12 "$TMP/out" | sed 's/^/          | /'
  else
    why "your program printed nothing on stdout."
  fi
  if [ -s "$TMP/err" ]; then
    why "and on stderr:"
    head -4 "$TMP/err" | sed 's/^/          | /'
  fi
}

T='\([0-9]+\.[0-9]{2}s\)$'        # the "(0.31s)" at the end of a done line
P='\(pid [0-9]+\)'                # the "(pid 1234)" in the middle

echo "Running assignment self-checks"
echo "------------------------------"

# 1. one job, exit 0 ----------------------------------------------------------
printf 'true\n' > "$TMP/one.txt"
run_ra "$TMP/one.txt"
if has "^\[runall\] start job 1 $P: true$" \
   && has "^\[runall\] done  job 1 $P: exit 0 $T" \
   && has '^\[runall\] summary: 1 run, 1 succeeded, 0 failed$' \
   && [ $rc -eq 0 ]; then
  ok "runs one job and reports it exited with 0"
else
  bad "runs one job and reports it exited with 0 (rc=$rc)"; show_out
fi

# 2. every word reaches the program -------------------------------------------
printf 'echo alpha   beta\tgamma\n' > "$TMP/words.txt"
run_ra "$TMP/words.txt"
if grep -qx 'alpha beta gamma' "$TMP/out" && has "^\[runall\] done  job 1 $P: exit 0 $T"; then
  ok "splits the command on spaces and tabs and passes every word"
else
  bad "splits the command on spaces and tabs and passes every word"
  why "expected echo to print: alpha beta gamma"; show_out
fi

# 3. non-zero exit code -------------------------------------------------------
printf '%s/exitwith 42\n' "$H" > "$TMP/fail.txt"
run_ra "$TMP/fail.txt"
if has "^\[runall\] done  job 1 $P: exit 42 $T" \
   && has '^\[runall\] summary: 1 run, 0 succeeded, 1 failed$' \
   && [ $rc -eq 1 ]; then
  ok "reports a non-zero exit code, and runall itself exits with 1"
else
  bad "reports a non-zero exit code, and runall itself exits with 1 (rc=$rc)"; show_out
fi

# 4. killed by a signal -------------------------------------------------------
printf '%s/selfkill 9\n' "$H" > "$TMP/kill.txt"
run_ra "$TMP/kill.txt"
if has "^\[runall\] done  job 1 $P: killed by signal 9 $T" \
   && has '^\[runall\] summary: 1 run, 0 succeeded, 1 failed$'; then
  ok "reports a job that was killed by a signal"
else
  bad "reports a job that was killed by a signal"; show_out
fi

# 5. command not found --------------------------------------------------------
printf 'no_such_command_csc139 --help\necho still running\n' > "$TMP/missing.txt"
run_ra "$TMP/missing.txt"
if has "^\[runall\] done  job 1 $P: exit 127 $T" \
   && grep -q 'no_such_command_csc139' "$TMP/err" \
   && has "^\[runall\] done  job 2 $P: exit 0 $T" \
   && has '^\[runall\] summary: 2 run, 1 succeeded, 1 failed$'; then
  ok "missing command: child reports it on stderr, exits 127, next job still runs"
else
  bad "missing command: child reports it on stderr, exits 127, next job still runs"
  show_out
fi

# 6. nothing printed twice when stdout is a file ------------------------------
printf 'echo one\nno_such_command_csc139\necho three\n' > "$TMP/dup.txt"
run_ra "$TMP/dup.txt"
starts=$(grep -c '^\[runall\] start ' "$TMP/out")
dones=$(grep -c '^\[runall\] done ' "$TMP/out")
sums=$(grep -c '^\[runall\] summary' "$TMP/out")
if [ "$starts" -eq 3 ] && [ "$dones" -eq 3 ] && [ "$sums" -eq 1 ]; then
  ok "prints every line exactly once when output goes to a file"
else
  bad "prints every line exactly once when output goes to a file"
  why "expected 3 start lines, 3 done lines, 1 summary;" \
      "got $starts start, $dones done, $sums summary." \
      "Read docs/BEYOND_THE_SLIDES.md sections 2 and 3."
fi

# 7. comments and blank lines -------------------------------------------------
printf '# a comment\n\n   \ntrue\n   # an indented comment\n\ttrue\n' > "$TMP/comments.txt"
run_ra "$TMP/comments.txt"
if has '^\[runall\] summary: 2 run, 2 succeeded, 0 failed$' \
   && has "^\[runall\] done  job 2 $P: exit 0 $T"; then
  ok "skips comments and blank lines"
else
  bad "skips comments and blank lines"; show_out
fi

# 8. default is one at a time, in file order ----------------------------------
D="$TMP/seq"; mkdir -p "$D"
for i in 1 2 3 4; do echo "$H/probe $D 150"; done > "$TMP/seq.txt"
run_ra "$TMP/seq.txt"
max=$(cat "$D/max" 2>/dev/null || echo 0)
order=$(grep -oE '^\[runall\] start job [0-9]+' "$TMP/out" | awk '{print $4}' | tr '\n' ' ')
if [ "$max" = "1" ] && [ "$order" = "1 2 3 4 " ]; then
  ok "without -j, runs one job at a time, in file order"
else
  bad "without -j, runs one job at a time, in file order"
  why "most jobs running at once: $max (expected 1); start order: ${order:-none} (expected 1 2 3 4)"
fi

# 9. -j 3 means three at once, never more -------------------------------------
D="$TMP/par"; mkdir -p "$D"
for i in 1 2 3 4 5 6 7; do echo "$H/probe $D 300"; done > "$TMP/par.txt"
run_ra -j 3 "$TMP/par.txt"
max=$(cat "$D/max" 2>/dev/null || echo 0)
if [ "$max" = "3" ] && has '^\[runall\] summary: 7 run, 7 succeeded, 0 failed$'; then
  ok "-j 3 runs three jobs at once, and never more than three"
else
  bad "-j 3 runs three jobs at once, and never more than three"
  why "most jobs running at once: $max (expected exactly 3)"
fi

# 10. a free slot is filled immediately, not after the whole group ------------
D="$TMP/fill"; mkdir -p "$D"
{ echo "$H/probe $D 1500"; for i in 1 2 3; do echo "$H/probe $D 100"; done; } > "$TMP/fill.txt"
run_ra -j 2 "$TMP/fill.txt"
s3=$(line_of '^\[runall\] start job 3 ')
d1=$(line_of '^\[runall\] done  job 1 ')
if [ "$s3" -gt 0 ] && [ "$d1" -gt 0 ] && [ "$s3" -lt "$d1" ]; then
  ok "starts the next job as soon as ANY running job finishes"
else
  bad "starts the next job as soon as ANY running job finishes"
  why "job 1 takes 1.5 s and jobs 2-4 take 0.1 s, with -j 2." \
      "Job 3 should start as soon as job 2 is done, long before job 1 is."
  show_out
fi

# 11. waits for every child ---------------------------------------------------
D="$TMP/wait"; mkdir -p "$D"
for i in 1 2 3 4 5; do echo "$H/probe $D 300"; done > "$TMP/wait.txt"
run_ra -j 5 "$TMP/wait.txt"
finished=$(ls "$D" 2>/dev/null | grep -c '^done\.')
if [ "$finished" -eq 5 ]; then
  ok "waits for every job to finish before exiting"
else
  bad "waits for every job to finish before exiting"
  why "when runall exited, only $finished of 5 jobs had finished."
fi

# 12. really fork + exec ------------------------------------------------------
syms=$(nm -u "$BIN" 2>/dev/null)
if echo "$syms" | grep -Eq '(^|[[:space:]])(system|popen|posix_spawnp?|vfork)(@|$)'; then
  bad "uses fork() and exec, not system()/popen()/posix_spawn()"
  why "found: $(echo "$syms" | grep -Eo '(system|popen|posix_spawnp?|vfork)' | sort -u | tr '\n' ' ')"
elif echo "$syms" | grep -Eq '(^|[[:space:]])fork(@|$)' \
     && echo "$syms" | grep -Eq '(^|[[:space:]])execv(p|e|pe)?(@|$)'; then
  ok "uses fork() and exec, not system()/popen()/posix_spawn()"
else
  bad "uses fork() and exec, not system()/popen()/posix_spawn()"
  why "your compiled program never calls fork() and execvp()."
fi

echo "------------------------------"
echo "passed: $pass   failed: $fail"

if [ $fail -eq 0 ]; then
  echo
  echo "  All checks passed. Your completion code is:"
  echo
  echo "      $COMPLETION_CODE"
  echo
  echo "  Paste it into Question 1 of the Canvas quiz."
  exit 0
fi

echo
echo "  Fix the failures above, run 'make test' again, and the completion"
echo "  code will appear here."
exit 1
