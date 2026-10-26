.PHONY: check test verify all

all: check test verify

check:
	@find bin dotlink scripts profiles env -type f \( -executable -o -name '*.sh' \) -print0 2>/dev/null | sort -z | xargs -0 -n1 bash -n --
	@echo "shell syntax checks passed"

test:
	@dotlink/tests/run.sh
	@bash dotlink/tests/fish.sh
	@python3 dotlink/tests/shells.py
	@python3 dotlink/tests/zsh-native.py
	@python3 dotlink/tests/zsh-integrations.py
	@python3 dotlink/tests/shells-tools.py

verify:
	@scripts/verify-dotfiles-boundary.sh
