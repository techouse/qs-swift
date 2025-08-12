# Makefile

# Apply to all Swift test invocations from this Makefile
export SWIFT_DETERMINISTIC_HASHING=1

.PHONY: build help test coverage coverage-html coverage-release clean reset test test-release

help:
	@printf "%-20s %s\n" "Target" "Description"
	@printf "%-20s %s\n" "------" "-----------"
	@make -pqR : 2>/dev/null \
		| awk -v RS= -F: '/^# File/,/^# Finished Make data base/ {if ($$1 !~ "^[#.]") {print $$1}}' \
		| sort \
		| egrep -v -e '^[^[:alnum:]]' -e '^$@$$' \
		| xargs -I _ sh -c 'printf "%-20s " _; make _ -nB | (grep -i "^# Help:" || echo "") | tail -1 | sed "s/^# Help: //g"'

build:
	@# Help: Build the package
	@swift build

build-release:
	@# Help: Build the package
	@swift build -c release

build-clean-release:
	@# Help: Clean and rebuild the package
	@# This is useful when you want to ensure a clean build without artifacts from previous builds
	@make clean
	@make build-release

clean:
	@# Help: Clean build artifacts
	@swift package clean
	@rm -rf .build
	@rm -rf coverage output

reset:
	@# Help: Reset build artifacts
	@make clean
	@swift package reset

test:
	@# Help: Run Swift tests (deterministic hashing)
	@swift test -q

test-release:
	@# Help: Run Swift tests (deterministic hashing)
	@swift test -q -c release

coverage:
	@# Help: Run tests and generate code coverage report
	@bash scripts/coverage.sh

coverage-html:
	@# Help: Generate HTML code coverage report
	@bash scripts/coverage.sh --html

coverage-release:
	@# Help: Run tests and generate code coverage report for release build
	@bash scripts/coverage.sh --release --htmled coverage output
	@rm -rf coverage
