# CSC 139 - Assignment 2: `runall`

**100 points.** Write a program that runs a list of commands, each in its own
child process, several at a time. It uses `fork()` to create each child and
`exec` to turn the child into the command. Then watch it happen with `strace`.

## Where you will work

**GitHub Codespaces**, the same as Assignment 1. That is the environment for
this assignment: not your laptop, not a VM, not your own Linux install.
Everything is already installed there, everyone gets the same setup, and it is
what your work is graded against.

Do not write this on macOS. Process creation and tracing work differently
there, and your code is graded on Linux.

**Setup instructions: [docs/SETUP.md](docs/SETUP.md)** take about five minutes
and need nothing installed. If you still have your Assignment 1 codespace, stop
it. You need a new one, made from *this* repository.

## Step 1 - Verify your environment

In the terminal at the bottom of your codespace:

```bash
make check-env
```

Every line must say `PASS`. If anything says `FAIL`, post on Canvas with a
screenshot before you start coding.

## Step 2 - Read what the slides did not cover

**[docs/BEYOND_THE_SLIDES.md](docs/BEYOND_THE_SLIDES.md)** covers everything
this assignment needs beyond the Chapter 3 lecture:

- `execvp` and argv arrays
- what to do when exec fails
- `_exit()` and the stdout buffer
- decoding the status that `wait()` gives you
- `wait()` with several children
- `strtok`

Read it before you write any code. The four TODOs point back to its sections.

## Step 3 - Write the program

Everything you write goes in **`src/runall.c`**. The rules are at the top, and
there are four `TODO`s, each with a sketch of what to do. Reading the job file,
the `-j` option, timing and the summary are already written for you.

```bash
make                    # build
make run                # run the demo: ./runall -j 2 examples/demo.txt
```

### What `runall` does

```bash
./runall jobs.txt          # run the jobs one at a time
./runall -j 4 jobs.txt     # run up to four at once
```

A **job file** has one command per line. Blank lines and lines starting with
`#` are skipped. Words are separated by spaces or tabs.

```
# jobs.txt
echo hello
sleep 1
ls -l /nonexistent
```

`runall` starts the jobs in file order, never with more than `N` running at
once. The moment *any* job finishes, it starts the next one. For each job it
prints a `start` line and a `done` line, then a summary at the end:

```
[runall] start job 1 (pid 4639): echo hello
hello
[runall] start job 2 (pid 4640): sleep 1
[runall] done  job 1 (pid 4639): exit 0 (0.00s)
[runall] start job 3 (pid 4641): ls -l /nonexistent
ls: cannot access '/nonexistent': No such file or directory
[runall] done  job 3 (pid 4641): exit 2 (0.00s)
[runall] done  job 2 (pid 4640): exit 0 (1.00s)
[runall] summary: 3 run, 2 succeeded, 1 failed
```

(That run used `-j 2`.) A job killed by a signal is reported as
`killed by signal 9` instead of `exit ...`. The exact format strings are
defined at the top of `src/runall.c`. Use them as they are, because the checks
match them character for character.

`runall` itself exits with `0` if every job succeeded and `1` if any failed.

### Rules

- Every job runs in its own child: `fork()`, then `execvp()` in the child.
  **No `system()`, `popen()` or `posix_spawn()`.** The checks inspect your
  compiled program for them.
- If exec fails, the child prints why with `perror` and ends with `_exit(127)`.
- Never more than `N` jobs at once. Fill a free slot as soon as one opens.
- Wait for every child before `runall` finishes.
- Your own debugging output goes to `stderr`, not `stdout`.

## Step 4 - Test

```bash
make test
```

Twelve checks. When all twelve pass, the script prints a **completion code**.
You need it for the quiz, so keep it.

The checks run your program with a 20-second time limit. A version that hangs,
or that keeps creating processes, fails a check instead of freezing your
codespace.

## Step 5 - Trace and measure

```bash
make trace           # fork/exec/wait calls of every process -> trace.txt
make trace-summary   # counted summary across runall and all its children
make experiment      # the same 8 jobs at -j 1, 2, 3, 4, 8 (~10 seconds)
```

What to look for: [docs/TRACING.md](docs/TRACING.md). The quiz asks for numbers
from `make trace-summary` and `make experiment`, so run both before you start
it.

## Step 6 - Submit

Submission is the **Canvas quiz "Assignment 2: runall"**. There is nothing to
upload anywhere else. It asks for:

1. your completion code from `make test`
2. a few numbers from your own `make trace-summary` and `make experiment` runs
3. some questions about fork, exec and wait
4. your finished `src/runall.c`, pasted into the last question

Run `make test`, `make trace-summary` and `make experiment` **before** you open
the quiz, so the numbers are in front of you.

## A note on AI

Course policy applies: use it to understand the material, but do not submit its
work as your own. The exam will ask you about fork, exec and wait, and about
this program. A program you did not write is a question you cannot answer.
