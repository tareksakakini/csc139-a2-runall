/* Test helper used by the concurrency checks.
 *
 *   probe DIR MS
 *
 * Records that it is running, sleeps MS milliseconds, records that it is
 * finished. Across every probe sharing DIR it keeps:
 *   DIR/count   how many probes are running right now
 *   DIR/max     the most that were ever running at the same moment
 *   DIR/done.N  one file per probe that ran to completion (N = its pid)
 * A lock file serialises the updates, so the numbers are exact.        */
#define _DEFAULT_SOURCE
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/file.h>
#include <time.h>
#include <unistd.h>

static int read_int(const char *path)
{
    FILE *f = fopen(path, "r");
    int v = 0;
    if (f) { if (fscanf(f, "%d", &v) != 1) v = 0; fclose(f); }
    return v;
}

static void write_int(const char *path, int v)
{
    FILE *f = fopen(path, "w");
    if (f) { fprintf(f, "%d\n", v); fclose(f); }
}

static void adjust(const char *dir, int delta)
{
    char lock[4096], count[4096], max[4096];
    snprintf(lock,  sizeof lock,  "%s/lock",  dir);
    snprintf(count, sizeof count, "%s/count", dir);
    snprintf(max,   sizeof max,   "%s/max",   dir);

    int fd = open(lock, O_RDWR | O_CREAT, 0644);
    if (fd < 0) { perror(lock); exit(3); }
    flock(fd, LOCK_EX);
    int c = read_int(count) + delta;
    write_int(count, c);
    if (c > read_int(max))
        write_int(max, c);
    flock(fd, LOCK_UN);
    close(fd);
}

int main(int argc, char *argv[])
{
    if (argc != 3) { fprintf(stderr, "usage: probe DIR MS\n"); return 3; }
    const char *dir = argv[1];
    long ms = atol(argv[2]);

    adjust(dir, +1);
    struct timespec ts = { ms / 1000, (ms % 1000) * 1000000L };
    nanosleep(&ts, NULL);
    adjust(dir, -1);

    char done[4096];
    snprintf(done, sizeof done, "%s/done.%d", dir, (int)getpid());
    write_int(done, 1);
    return 0;
}
