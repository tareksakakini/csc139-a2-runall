CC       = gcc
CFLAGS   = -std=c17 -Wall -Wextra -Wpedantic -g
TARGET   = runall
SRC      = src/runall.c
HELPERS  = tests/bin/exitwith tests/bin/selfkill tests/bin/probe

.PHONY: all clean check-env test run trace trace-summary experiment

all: $(TARGET) $(HELPERS)

$(TARGET): $(SRC)
	$(CC) $(CFLAGS) -o $@ $<

# Small programs the self-checks use as jobs. You do not need to touch them.
tests/bin/%: tests/helpers/%.c
	@mkdir -p tests/bin
	@$(CC) $(CFLAGS) -o $@ $<

# ---------------------------------------------------------------------------
# check-env - run this FIRST, on day one. It proves your environment can do
# everything this assignment needs. If anything says FAIL, post on Canvas
# before you start coding.
# ---------------------------------------------------------------------------
check-env:
	@echo "CSC 139 environment check"
	@echo "-------------------------"
	@printf 'kernel      : '; uname -sr
	@printf 'gcc         : '; if command -v gcc >/dev/null 2>&1; then gcc --version | head -1; else echo '(not installed)'; fi
	@printf 'make        : '; if command -v make >/dev/null 2>&1; then make --version | head -1; else echo '(not installed)'; fi
	@printf 'strace      : '; if command -v strace >/dev/null 2>&1; then strace --version | head -1; else echo '(not installed)'; fi
	@printf 'gdb         : '; if command -v gdb >/dev/null 2>&1; then gdb --version | head -1; else echo '(not installed)'; fi
	@echo "-------------------------"
	@if [ "$$(uname -s)" != "Linux" ]; then \
		echo 'platform    : FAIL - this is not Linux. Open your codespace.'; \
		exit 1; \
	fi
	@if strace -f -o /dev/null /bin/true >/dev/null 2>&1; then \
		echo 'strace trace: PASS - you can trace system calls here'; \
	else \
		echo 'strace trace: FAIL - ptrace is blocked in this environment'; \
		echo '              Post on Canvas with a screenshot of this output.'; \
		exit 1; \
	fi
	@if man 3 execvp >/dev/null 2>&1; then \
		echo 'man 3 execvp: PASS'; \
	else \
		echo 'man 3 execvp: (missing - not fatal, use man7.org instead)'; \
	fi
	@echo "-------------------------"
	@echo "Environment looks good. Start with docs/BEYOND_THE_SLIDES.md, then src/runall.c"

test: all
	@bash tests/run_tests.sh

# Run the demo job file two at a time and watch what happens.
run: all
	@echo './$(TARGET) -j 2 examples/demo.txt'
	@./$(TARGET) -j 2 examples/demo.txt; echo "(runall itself exited with status $$?)"

# ---------------------------------------------------------------------------
# trace / trace-summary - watch fork, exec and wait happen. -f makes strace
# follow every child runall creates, not just runall itself.
# ---------------------------------------------------------------------------
trace: $(TARGET)
	strace -f -e trace=clone,clone3,fork,vfork,execve,wait4,exit_group \
	       -o trace.txt ./$(TARGET) -j 2 examples/trace_demo.txt || true
	@echo
	@echo "Trace written to trace.txt ($$(wc -l < trace.txt) lines)."
	@echo "Each line starts with the pid of the process that made the call."

trace-summary: $(TARGET)
	strace -f -c ./$(TARGET) -j 2 examples/trace_demo.txt || true

# ---------------------------------------------------------------------------
# experiment - the same eight half-second jobs, run with different -j
# values. Times are measured without strace. Takes about ten seconds.
# ---------------------------------------------------------------------------
experiment: $(TARGET)
	@echo "8 jobs, each /bin/sleep 0.5, varying -j"
	@echo
	@printf '%-6s %-10s\n' "-j" SECONDS
	@for j in 1 2 3 4 8; do \
		start=$$(date +%s.%N); \
		./$(TARGET) -j $$j examples/sleepy.txt >/dev/null 2>&1; \
		end=$$(date +%s.%N); \
		t=$$(echo "$$end $$start" | awk '{printf "%.2f", $$1-$$2}'); \
		printf '%-6s %-10s\n' "$$j" "$$t"; \
	done

clean:
	rm -f $(TARGET) *.o trace*.txt
	rm -rf tests/tmp tests/bin
