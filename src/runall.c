/*
 * CSC 139 - Operating System Principles
 * Assignment 2: runall
 *
 * WHAT YOU ARE BUILDING
 *   A program that runs every command in a job file, each one in its own
 *   child process, with at most N of them running at the same time:
 *
 *       ./runall jobs.txt          one job at a time
 *       ./runall -j 4 jobs.txt     up to four jobs at once
 *
 *   It reports when each job starts and how it ended, then prints a summary.
 *
 * RULES
 *   1. Every job runs in its own child process, created with fork() and
 *      turned into the command with execvp(). Do NOT use system(), popen()
 *      or posix_spawn() - the self-checks inspect the compiled program.
 *   2. Never more than N jobs running at once (-j N, default 1). As soon as
 *      ANY running job finishes, start the next one. Do not wait for a whole
 *      group to finish before starting more.
 *   3. If exec fails (no such command), the CHILD reports why with perror()
 *      and ends itself with _exit(127). See docs/BEYOND_THE_SLIDES.md,
 *      sections 2 and 3, for why this matters so much.
 *   4. Wait for every child you create. runall must not finish while any job
 *      is still running.
 *   5. Print progress using the four FMT_ formats below, exactly. Anything
 *      else you want to print (errors, debugging) goes to stderr.
 *   6. Exit with status 0 if every job succeeded (exited with status 0),
 *      and 1 otherwise.
 *
 * WHAT IS ALREADY WRITTEN FOR YOU
 *   Reading the job file, the -j option, timing, the summary, and a helper
 *   that finds a job by its pid. Read them - you will call two of them.
 *
 * WHAT YOU WRITE - four TODOs, in this order:
 *   TODO 1  parse_argv()   split one command line into an argv array
 *   TODO 2  start_job()    fork + exec one job
 *   TODO 3  report_job()   decode the status that wait() gave you
 *   TODO 4  run_all()      the loop that keeps up to N jobs running
 *
 * BEFORE YOU START, read docs/BEYOND_THE_SLIDES.md. It covers everything
 * this assignment uses that the Chapter 3 slides did not: execvp and argv
 * arrays, what to do when exec fails, _exit and the stdout buffer, decoding
 * the wait() status, and strtok.
 *
 * AND READ THE MANUAL:  man 3 execvp  |  man 2 wait  |  man 3 strtok
 */

/* Ask the C library for the POSIX functions (clock_gettime and friends),
 * which strict -std=c17 would otherwise hide. Must come before any #include. */
#define _POSIX_C_SOURCE 200809L

#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

#define MAX_JOBS      256   /* most commands a job file may hold      */
#define MAX_ARGS      64    /* most words in one command               */
#define LINE_LEN      1024  /* longest command line, in characters     */
#define MAX_PARALLEL  64    /* largest value accepted for -j           */

/* The exact output formats. The self-checks match these character for
 * character, so use them as they are. */
#define FMT_START    "[runall] start job %d (pid %d): %s\n"
#define FMT_EXITED   "[runall] done  job %d (pid %d): exit %d (%.2fs)\n"
#define FMT_KILLED   "[runall] done  job %d (pid %d): killed by signal %d (%.2fs)\n"
#define FMT_SUMMARY  "[runall] summary: %d run, %d succeeded, %d failed\n"

struct job {
    int    number;                /* 1, 2, 3 ... in file order              */
    char   text[LINE_LEN];        /* the command exactly as written         */
    char   words[LINE_LEN];       /* scratch copy that parse_argv chops up  */
    char  *argv[MAX_ARGS + 1];    /* the words, followed by a NULL          */
    pid_t  pid;                   /* child's pid once started, else 0       */
    double start;                 /* now_seconds() when it was started      */
};

static struct job jobs[MAX_JOBS];
static int        njobs;

/* ------------------------------------------------------------------ */
/* Provided helpers                                                     */
/* ------------------------------------------------------------------ */

/* Seconds since some fixed moment, with nanosecond resolution. Only the
 * DIFFERENCE between two calls means anything: end - start = elapsed. */
static double now_seconds(void)
{
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (double)ts.tv_sec + (double)ts.tv_nsec / 1e9;
}

/* The job whose child has this pid, or NULL if there is none.
 * wait() tells you WHICH child finished by returning its pid; this turns
 * that pid back into the job it belongs to. */
static struct job *find_job(pid_t pid)
{
    for (int i = 0; i < njobs; i++)
        if (jobs[i].pid == pid)
            return &jobs[i];
    return NULL;
}

/* ------------------------------------------------------------------ */
/* TODO 1 - split a command line into words                             */
/* ------------------------------------------------------------------ */
/*
 * words     a line such as  "ls   -l\t/tmp"  (you may modify it in place)
 * argv      where to put a pointer to each word
 * max_args  the most words allowed
 *
 * Words are separated by one or more spaces or tabs. After the call:
 *     argv[0] -> "ls"   argv[1] -> "-l"   argv[2] -> "/tmp"   argv[3] = NULL
 * The NULL after the last word is REQUIRED - execvp() finds the end of the
 * list by looking for it.
 *
 * Returns the number of words (3 above), or -1 if there are more than
 * max_args of them.
 *
 * Use strtok(words, " \t") for the first word and strtok(NULL, " \t") for
 * each one after it. It returns NULL when there are no words left.
 * (docs/BEYOND_THE_SLIDES.md, section 6.)
 *
 * This is called for you, by load_jobs(), once per command in the file.
 */
static int parse_argv(char *words, char *argv[], int max_args)
{
    (void)words;
    (void)max_args;

    argv[0] = NULL;
    return 0;       /* TODO: replace this. 0 words makes every line an error. */
}

/* ------------------------------------------------------------------ */
/* Provided: read the job file                                          */
/* ------------------------------------------------------------------ */
/*
 * One command per line. Blank lines, and lines whose first non-blank
 * character is '#', are skipped. Fills jobs[0..njobs-1]: number, text,
 * words and argv. Returns 0 on success, -1 (after printing why) on error.
 */
static int load_jobs(const char *path)
{
    FILE *fp = fopen(path, "r");
    if (fp == NULL) {
        perror(path);
        return -1;
    }

    char line[LINE_LEN + 2];
    int  lineno = 0;
    while (fgets(line, sizeof line, fp) != NULL) {
        lineno++;
        size_t len = strcspn(line, "\n");
        if (line[len] != '\n' && !feof(fp)) {
            fprintf(stderr, "%s:%d: line is longer than %d characters\n",
                    path, lineno, LINE_LEN);
            fclose(fp);
            return -1;
        }
        line[len] = '\0';

        char *p = line + strspn(line, " \t");   /* skip leading blanks */
        if (*p == '\0' || *p == '#')
            continue;                            /* blank or comment    */

        if (njobs == MAX_JOBS) {
            fprintf(stderr, "%s: more than %d jobs\n", path, MAX_JOBS);
            fclose(fp);
            return -1;
        }

        struct job *j = &jobs[njobs];
        j->number = njobs + 1;
        snprintf(j->text,  sizeof j->text,  "%s", p);
        snprintf(j->words, sizeof j->words, "%s", p);
        if (parse_argv(j->words, j->argv, MAX_ARGS) < 1) {
            fprintf(stderr, "%s:%d: could not split this line into words\n",
                    path, lineno);
            fclose(fp);
            return -1;
        }
        njobs++;
    }

    fclose(fp);
    return 0;
}

/* ------------------------------------------------------------------ */
/* TODO 2 - start one job                                               */
/* ------------------------------------------------------------------ */
/*
 * Create a child process that runs j's command. Returns 0 if the child was
 * created, -1 if fork() failed (report it with perror first).
 *
 * Sketch:
 *   - fflush(stdout) BEFORE fork(). (BEYOND_THE_SLIDES.md, section 3.)
 *   - pid = fork()
 *       pid <  0  -> fork failed: perror("fork"), return -1
 *       pid == 0  -> you are the CHILD:
 *                      execvp(j->argv[0], j->argv);
 *                    if execvp returns at all, it failed. perror() with the
 *                    command name, then _exit(127). Never return from here -
 *                    a child that returns keeps running runall's own loop.
 *       pid >  0  -> you are the PARENT: record j->pid and j->start
 *                    (now_seconds()), print FMT_START, return 0.
 *
 * FMT_START takes: j->number, (int)pid, j->text
 */
static int start_job(struct job *j)
{
    (void)j;

    fprintf(stderr, "start_job() is not implemented yet.\n");
    return -1;
}

/* ------------------------------------------------------------------ */
/* TODO 3 - report how a job ended                                      */
/* ------------------------------------------------------------------ */
/*
 * status is the int that wait() filled in for this job's child.
 * Print ONE line and return 1 if the job succeeded, 0 if it failed.
 *
 *   It exited normally        WIFEXITED(status) is true.
 *                             The exit code is WEXITSTATUS(status).
 *                             Print FMT_EXITED. Success means exit code 0.
 *   It was killed by a signal WIFSIGNALED(status) is true.
 *                             The signal number is WTERMSIG(status).
 *                             Print FMT_KILLED. That is always a failure.
 *
 * FMT_EXITED takes: j->number, (int)j->pid, exit code, elapsed seconds
 * FMT_KILLED takes: j->number, (int)j->pid, signal number, elapsed seconds
 * elapsed = now_seconds() - j->start
 *
 * (BEYOND_THE_SLIDES.md, section 4.)
 */
static int report_job(struct job *j, int status)
{
    (void)j;
    (void)status;

    return 0;
}

/* ------------------------------------------------------------------ */
/* TODO 4 - keep up to max_parallel jobs running until all are done     */
/* ------------------------------------------------------------------ */
/*
 * Runs jobs[0..njobs-1] in file order and returns how many FAILED
 * (a job that could not be started counts as failed).
 *
 * Keep three counters: next (the next job to start), running (how many
 * children are alive right now) and failed.
 *
 *   while there are jobs left to start, or children still running:
 *       while running < max_parallel and there are jobs left to start:
 *           start_job(&jobs[next]); if it worked, running++ (else failed++)
 *           next++
 *       if nothing is running, go round again
 *       pid = wait(&status)          -- blocks until ANY child ends
 *       j   = find_job(pid)
 *       if report_job(j, status) says it failed, failed++
 *       running--
 *
 * wait() returns -1 on error. If errno is EINTR just go round again;
 * anything else, perror("wait") and stop the loop.
 * (BEYOND_THE_SLIDES.md, section 5.)
 */
static int run_all(int max_parallel)
{
    (void)max_parallel;
    (void)find_job;
    (void)start_job;
    (void)report_job;
    (void)now_seconds;

    fprintf(stderr, "run_all() is not implemented yet.\n");
    return njobs;
}

/* ------------------------------------------------------------------ */
/* Provided: main                                                       */
/* ------------------------------------------------------------------ */

static void usage(const char *prog)
{
    fprintf(stderr, "usage: %s [-j N] JOBFILE\n", prog);
    exit(2);
}

int main(int argc, char *argv[])
{
    int max_parallel = 1;
    const char *path = NULL;

    if (argc == 2) {
        path = argv[1];
    } else if (argc == 4 && strcmp(argv[1], "-j") == 0) {
        char *end = NULL;
        long v = strtol(argv[2], &end, 10);
        if (end == argv[2] || *end != '\0' || v < 1 || v > MAX_PARALLEL) {
            fprintf(stderr, "-j must be a number from 1 to %d\n", MAX_PARALLEL);
            return 2;
        }
        max_parallel = (int)v;
        path = argv[3];
    } else {
        usage(argv[0]);
    }

    if (load_jobs(path) != 0)
        return 2;

    int failed = run_all(max_parallel);

    printf(FMT_SUMMARY, njobs, njobs - failed, failed);
    return failed == 0 ? 0 : 1;
}
