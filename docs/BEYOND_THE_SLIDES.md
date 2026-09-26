# Beyond the slides

The Chapter 3 slides showed you `fork()`, `execlp()`, `wait()` and `exit()`,
one child at a time. `runall` uses all of those, plus a handful of things the
slides did not cover. **Everything you need that was not in lecture is on this
page.** Read it once before you start, then come back to each section when you
reach the TODO that points to it.

| Section | You need it for |
|---|---|
| [1. `execvp` and the argv array](#1-execvp-and-the-argv-array) | TODO 1, TODO 2 |
| [2. When exec fails](#2-when-exec-fails) | TODO 2 |
| [3. `_exit()`, `exit()` and the stdout buffer](#3-_exit-exit-and-the-stdout-buffer) | TODO 2 |
| [4. Reading the status that `wait()` gives you](#4-reading-the-status-that-wait-gives-you) | TODO 3 |
| [5. `wait()` with several children](#5-wait-with-several-children) | TODO 4 |
| [6. Splitting a line into words with `strtok`](#6-splitting-a-line-into-words-with-strtok) | TODO 1 |
| [7. Measuring elapsed time](#7-measuring-elapsed-time) | already written for you |
| [8. Why `runall` is not a shell](#8-why-runall-is-not-a-shell) | understanding the job file |

---

## 1. `execvp` and the argv array

There is no single function called `exec`. There is a family of six, and their
names are a code:

| Letter | Means |
|---|---|
| `l` | the arguments are a **l**ist, written out in the call itself |
| `v` | the arguments are a **v**ector, an array you built beforehand |
| `p` | search the directories in `$PATH` for the program, the way your terminal does |

The slides used `execlp`, a **list**:

```c
execlp("ls", "ls", "-l", "/tmp", NULL);
```

That only works when you know, while writing the program, exactly how many
arguments there will be. `runall` reads its commands from a file at run time.
One line might have one word, the next might have twelve. You cannot write a
function call with a number of arguments you do not know yet, so you need the
**vector** version and an array:

```c
char *args[] = { "ls", "-l", "/tmp", NULL };
execvp(args[0], args);
```

Three rules for that array, and all three matter:

1. **`args[0]` is the program's own name.** That is a convention, and every
   program expects it. So the command name appears twice in the call: once as
   the file to run (the first parameter), and once as `args[0]`.
2. **The last element must be `NULL`.** `execvp` does not take a count. It finds
   the end of your list by walking forward until it hits `NULL`. Leave it out
   and it keeps reading whatever garbage comes next in memory.
3. **The strings must stay alive until the call.** Pointers into a buffer that
   has already been overwritten or freed point at garbage.

About the `p`: if the name contains a slash (`./runall`, `tests/bin/probe`,
`/bin/sleep`), `execvp` uses it as a path and does not search. If it has no
slash (`ls`, `echo`), it tries each directory in `$PATH` in turn, just like
typing the command in a terminal. Try `echo $PATH` to see the list.

In `runall`, TODO 1 builds exactly this array for each job (in `j->argv`), and
TODO 2 hands it to `execvp(j->argv[0], j->argv)`.

---

## 2. When exec fails

The slides said that exec does not return. That is true **when it works**. When
it fails, it returns `-1` and sets `errno`. The usual reasons are that there is
no such program (`ENOENT`), or that the file is not executable (`EACCES`).

This is the most important paragraph on this page. **If `execvp` returns, the
child is still running your program.** It is a complete copy of `runall`,
sitting in the middle of `start_job()`, with its own copy of the job table and
of all your counters. If you let it `return` from `start_job()`, it goes back
into `run_all()`'s loop and carries on starting jobs, and now you have two
`runall`s. With several bad commands in the file it gets worse each time.

So the child must end itself, right there:

```c
if (pid == 0) {                      /* child */
    execvp(j->argv[0], j->argv);
    perror(j->argv[0]);              /* only reached if exec failed */
    _exit(127);
}
```

`perror` prints the command name followed by the reason, for example
`no_such_command: No such file or directory`, on stderr.

**Why 127?** It is what shells use for "command not found". Try it in your
codespace terminal:

```bash
no_such_command
echo $?          # prints the exit status of the last command: 127
```

The parent then sees an ordinary child that exited with status 127, and
reports it the same way as any other failure.

**Why `_exit` and not `exit`?** That is the next section.

---

## 3. `_exit()`, `exit()` and the stdout buffer

`printf` does not write to the screen when you call it. It copies your text into
a **buffer** inside your process's memory. The C library hands that buffer to
the kernel with a real `write()` system call later:

- when stdout is a **terminal**, at the end of every line;
- when stdout is a **file or a pipe**, only when the buffer fills up (several
  kilobytes) or when the program exits.

Now remember what `fork()` does: it copies the parent's memory. **That includes
the buffer, and any text sitting in it that has not been written yet.** Now
there are two copies of those lines, one in each process, and each process will
write its copy out when it gets around to it.

You can see this for yourself. Save this as `dup.c`:

```c
#include <stdio.h>
#include <unistd.h>

int main(void)
{
    printf("printed once, before fork\n");
    fork();
    return 0;
}
```

```bash
gcc -o dup dup.c
./dup                 # to the terminal: one line
./dup > out.txt       # to a file...
cat out.txt           # ...two lines
```

Same program, same code, different output, depending only on where stdout goes.

What this means for `runall`:

- If the child **execs successfully**, its memory is replaced, buffer and all.
  The copied text is thrown away. No harm done.
- If exec **fails** and the child calls `exit()`, `exit()` flushes stdio
  buffers on the way out. The parent's unwritten lines come out a second time,
  from the child. The self-checks send `runall`'s output to a file, so they will
  catch this.

There are two fixes, and you should do both:

1. **Call `fflush(stdout)` right before `fork()`.** That forces anything
   buffered out first, so the child starts with an empty buffer.
2. **In the child, end with `_exit()`, not `exit()`.** `_exit` is the raw
   system call. It ends the process immediately, without flushing stdio buffers
   and without running anything else registered to run at exit. That is exactly
   right for a child that failed to become something else.

`_exit` is declared in `<unistd.h>`. In the parent, and everywhere else in your
program, `exit()` and `return` from `main` are still correct.

---

## 4. Reading the status that `wait()` gives you

`wait(&status)` fills in an `int`. **That int is not the exit code.** The kernel
packs several facts into it: how the child ended, and either its exit code or
the signal that killed it. A child that calls `exit(3)` produces a status of
`768` on Linux, not `3`.

Never print or compare `status` directly. Unpack it with these macros from
`<sys/wait.h>`:

| Macro | Answers |
|---|---|
| `WIFEXITED(status)` | Did the child end normally, by `exit()`, `_exit()` or returning from `main`? |
| `WEXITSTATUS(status)` | If so, what exit code did it give? (0 to 255) |
| `WIFSIGNALED(status)` | Was the child killed by a signal instead? |
| `WTERMSIG(status)` | If so, which signal? |

```c
int status;
pid_t pid = wait(&status);

if (WIFEXITED(status))
    printf("exited with %d\n", WEXITSTATUS(status));
else if (WIFSIGNALED(status))
    printf("killed by signal %d\n", WTERMSIG(status));
```

Only use `WEXITSTATUS` after `WIFEXITED` said yes. For a killed child it returns
a meaningless number.

**Exit codes.** By convention, `0` means success and anything else means some
kind of failure. Only the low 8 bits survive, so the range is 0 to 255, and
`exit(256)` looks exactly like `exit(0)` to the parent.

**Signals, just enough for this assignment.** A signal is a notification the
kernel delivers to a process. For several signals, the default reaction is to
end the process on the spot. A process ended this way never called `exit`, so
it has no exit code. The status records which signal it was instead. You will
meet these most often:

| Number | Name | Usually means |
|---|---|---|
| 2 | `SIGINT` | someone pressed Ctrl-C |
| 6 | `SIGABRT` | the program called `abort()`, or an `assert` failed |
| 9 | `SIGKILL` | killed with `kill -9`. It cannot be caught or ignored. |
| 11 | `SIGSEGV` | segmentation fault: the program touched memory it does not own |
| 15 | `SIGTERM` | a polite "please stop", the default for `kill` |

`runall` does not send signals and does not handle them. It only has to
**recognise** a job that was killed by one and report the number. The helper
`tests/bin/selfkill 9` kills itself with signal 9 so you can test that
(`make run` includes it).

---

## 5. `wait()` with several children

On the slides there was one child, so it was obvious which one `wait()` was
waiting for. `runall` has several running at once. Here is how `wait()`
behaves then:

- It blocks until **any one** of your children ends, and returns **that
  child's pid**. Children come back in the order they *finish*, not the order
  you started them. That is how `runall` can start the next job the moment a
  slot frees up.
- If a child had **already** finished before you called `wait()`, it has been
  a zombie since then, holding its status for you. `wait()` returns
  immediately with it. Nothing is lost by waiting late.
- If you have **no children at all**, `wait()` returns `-1` and sets `errno` to
  `ECHILD`. Only call it when you know something is running.
- Very rarely it can return `-1` with `errno` set to `EINTR`, meaning it was
  interrupted before anything happened. Just call it again.

To turn the returned pid back into a job, use the provided `find_job(pid)`.

You may come across `waitpid(pid, &status, options)`, which can wait for one
*particular* child. You do not need it here. `wait(&status)` is the same as
`waitpid(-1, &status, 0)`, where `-1` means "any child". You will see exactly
that `-1` in the trace, as `wait4(-1, ...)`.

---

## 6. Splitting a line into words with `strtok`

`strtok` from `<string.h>` walks through a string and returns one word at a
time:

```c
char line[] = "ls   -l\t/tmp";
char *w = strtok(line, " \t");      /* first call: pass the string   */
while (w != NULL) {
    printf("[%s]\n", w);
    w = strtok(NULL, " \t");        /* later calls: pass NULL        */
}
/* prints [ls] then [-l] then [/tmp] */
```

The second argument lists every character that separates words. Here that is a
space and a tab. Runs of separators count as one, so extra spaces are harmless.

Three things to know about it:

1. **It modifies the string.** It writes a `'\0'` over the separator after each
   word, so each word becomes its own C string.
2. **It returns pointers into your string, not copies.** The words live exactly
   as long as the string does. In `runall` that string is `j->words`, which
   lives in the global job table for the whole run. So storing those pointers
   in `j->argv` is safe.
3. **It remembers where it stopped**, between calls. That is why every call
   after the first passes `NULL`: it means "carry on from where you were".

Because of point 1, `load_jobs()` keeps two copies of each line: `j->text`,
which is never touched and is what you print, and `j->words`, which
`parse_argv()` is allowed to chop up.

---

## 7. Measuring elapsed time

This is already written for you in `now_seconds()`. It is here so you know what
it does.

`clock_gettime(CLOCK_MONOTONIC, ...)` reads a clock that only ever moves
forward, at a steady rate. It does not tell you the time of day. It is for
measuring **how long something took**: read it at the start, read it at the
end, and subtract.

The time-of-day clock is the wrong tool for this, because it can jump. Network
time synchronisation or daylight saving can move it backwards, and then a job
would appear to take a negative amount of time.

---

## 8. Why `runall` is not a shell

Each line of the job file is split on spaces and tabs, and the words go
straight to `execvp`. Nothing else is interpreted. That means:

| In a terminal | In a job file |
|---|---|
| `echo "hello world"` prints `hello world` | prints `"hello world"`, quotes included |
| `ls > out.txt` writes to a file | passes `>` and `out.txt` to `ls` as file names |
| `ls \| wc -l` is a pipeline | passes `\|`, `wc` and `-l` to `ls` |
| `echo *.c` lists your C files | prints `*.c` |
| `echo $HOME` prints your home directory | prints `$HOME` |

All of those are features of the **shell**, the program behind your terminal.
It does that work *before* it forks and execs. `runall` skips that step on
purpose, so everything you see is fork and exec with nothing in between.

One more, because it is a good operating-systems question: why can't `cd` be
an ordinary program like `ls`? Because `cd` has to change the current directory
of the *shell* itself. A child that changes its own directory and exits has no
effect at all on its parent. That is the same separation you saw in lecture,
where the child's copy of a variable was not the parent's. So `cd` is built
into the shell, and in a `runall` job file it fails with exit 127.
