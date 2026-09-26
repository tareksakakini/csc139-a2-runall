# Watching fork, exec and wait happen

In Assignment 1 you used `strace` to watch one process make system calls. This
time there are several processes, so every `strace` command here uses **`-f`**
("follow forks"). It traces `runall` and every child it creates, and it labels
each line with the pid of the process that made the call.

All three commands run `runall -j 2` on `examples/trace_demo.txt`, which holds
four jobs:

```
/bin/echo hello from job 1
/bin/sleep 0.2
/bin/true
/bin/false
```

The jobs use full paths on purpose. With a slash in the name, `execvp` does
not search `$PATH`, so each job is exactly one `execve` in the trace. Try
changing one to plain `echo` later and see what happens to the count.

---

## `make trace`: the story, call by call

This writes `trace.txt`, showing only the process-management calls. Open it.
Yours will have different pids, and lines may interleave differently, but it
will look like this:

```
4678  execve("./runall", ["./runall", "-j", "2", "examples/trace_demo.txt"], ...) = 0
4678  clone(child_stack=NULL, flags=CLONE_CHILD_CLEARTID|CLONE_CHILD_SETTID|SIGCHLD, ...) = 4679
4679  execve("/bin/echo", ["/bin/echo", "hello", "from", "job", "1"], ... <unfinished ...>
4678  clone(child_stack=NULL, flags=CLONE_CHILD_CLEARTID|CLONE_CHILD_SETTID|SIGCHLD, ...) = 4680
4680  execve("/bin/sleep", ["/bin/sleep", "0.2"], ... <unfinished ...>
4678  wait4(-1,  <unfinished ...>
4679  <... execve resumed>)             = 0
4679  exit_group(0)                     = ?
4679  +++ exited with 0 +++
4678  <... wait4 resumed>[{WIFEXITED(s) && WEXITSTATUS(s) == 0}], 0, NULL) = 4679
4678  clone(...) = 4681
...
```

How to read it:

- **The first column is the pid.** Here 4678 is `runall`. 4679, 4680 and so on
  are its children.
- **`fork()` appears as `clone`.** On Linux, `clone` is the one system call that
  creates new processes (and threads). The C library's `fork()` is a small
  wrapper that calls `clone` with the settings that mean "a new process that
  is a copy of me". The return value, `= 4679`, is the child's pid, exactly
  what `fork()` returned to the parent.
- **Every exec is `execve`.** `execvp`, `execlp` and the rest are all library
  wrappers around this single system call. Look at the second argument: it is
  the argv array your `parse_argv` built, printed out.
- **`wait()` appears as `wait4(-1, ...)`.** The `-1` means "any child". The
  part in square brackets is strace decoding the status for you, using the
  same macros you use in `report_job`. The return value is the pid of the
  child that finished.
- **`exit_group(0)`** is how a process ends. The next line, `+++ exited with 0 +++`,
  is strace's own note that the process is gone.
- **`<unfinished ...>` and `<... resumed>`** appear when two processes are in
  the middle of system calls at the same time. strace prints the start of one
  call, then another process's line, then the end of the first. That
  interleaving is concurrency, made visible.

Things to find in your own `trace.txt`:

1. Two `clone` calls before the first `wait4`. That is `-j 2` filling both slots.
2. A new `clone` right after each `wait4` returns. That is a freed slot being
   refilled immediately.
3. The `wait4` that returns the pid of the `sleep` job. It comes last even
   though that job was started second.
4. `exit_group(1)` from the `/bin/false` job, and the matching
   `WEXITSTATUS(s) == 1` in the `wait4` line that collects it.

---

## `make trace-summary`: the counts

This runs the same four jobs under `strace -f -c`, which prints a table with one
row per system call, totalled across **every** process: `runall` and all its
children together. The `calls` column is the one to read.

Before you run it, predict these two numbers. Then check them:

- How many `clone` calls? (Who calls `fork()`, and how many times?)
- How many `execve` calls? (Careful: how did `runall` itself get started?)

Most of the other rows (`mmap`, `openat`, `brk` and so on) come from each new
program loading itself and its libraries after `execve`. That start-up work
happens again in every child, and it is a large part of what makes starting a
process expensive.

---

## `make experiment`: why `-j` matters

This runs `examples/sleepy.txt`, eight jobs that each sleep for half a second,
at five different `-j` values. It times each run *without* strace.

```
-j     SECONDS
1      ...
2      ...
3      ...
4      ...
8      ...
```

Before you look at the numbers, work out what they should be. With `-j 1` the
jobs run one after another. With `-j 8` all of them run at once. The interesting
row is `-j 3`, where eight jobs do not divide evenly into slots. Think about how
many half-second "rounds" that takes.

Note that none of these jobs uses the CPU. `sleep` just waits. That is why
running eight of them at once on a two-core codespace still gives the full
speed-up. With CPU-heavy jobs, `-j` larger than the number of cores would stop
helping. That is a Chapter 5 (CPU scheduling) question.
