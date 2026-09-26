/* Test helper: exit with the status given on the command line.
 *   exitwith 42      -> exits with status 42                       */
#include <stdlib.h>

int main(int argc, char *argv[])
{
    return argc > 1 ? atoi(argv[1]) : 0;
}
