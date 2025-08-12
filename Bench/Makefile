# Makefile

.PHONY: help clean reset profile

# Apply to all Swift test invocations from this Makefile
export SWIFT_DETERMINISTIC_HASHING=1

help:
	@printf "%-20s %s\n" "Target" "Description"
	@printf "%-20s %s\n" "------" "-----------"
	@make -pqR : 2>/dev/null \
		| awk -v RS= -F: '/^# File/,/^# Finished Make data base/ {if ($$1 !~ "^[#.]") {print $$1}}' \
		| sort \
		| egrep -v -e '^[^[:alnum:]]' -e '^$@$$' \
		| xargs -I _ sh -c 'printf "%-20s " _; make _ -nB | (grep -i "^# Help:" || echo "") | tail -1 | sed "s/^# Help: //g"'

clean:
	@# Help: Clean build artifacts
	@swift package clean
	@rm -rf .build
	@rm -rf coverage output

reset:
	@# Help: Reset build artifacts
	@make clean
	@swift package reset

profile:
	@# Help: Generate profiling data
	@bash scripts/profile.sh
