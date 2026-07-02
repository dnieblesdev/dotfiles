.PHONY: check test verify all

all: check test verify

check:
	@find bin dotlink scripts profiles env -type f \( -executable -o -name '*.sh' \) -print0 2>/dev/null | sort -z | xargs -0 -n1 bash -n --
	@echo "shell syntax checks passed"

test:
	@dotlink/tests/run.sh

verify:
	@scripts/verify-bootstrap-split.sh
