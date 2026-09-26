/* Test helper: terminate by a signal instead of exiting normally.
 *   selfkill 9       -> killed by signal 9 (SIGKILL)                 */
#define _POSIX_C_SOURCE 200809L
#include <signal.h>
#include <stdlib.h>
#include <unistd.h>

int main(int argc, char *argv[])
{
    int sig = argc > 1 ? atoi(argv[1]) : SIGKILL;
    kill(getpid(), sig);
    pause();            /* not reached for a fatal signal */
    return 0;
}
