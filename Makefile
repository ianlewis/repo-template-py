# Copyright 2024 Ian Lewis
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

include include.mk

## Build
#####################################################################

.PHONY: all
all: test package ## Run all tests and build a release package.

.PHONY: package
package: .venv/.installed ## Create a release package.
	@# bash \
	$(REPO_ROOT)/.venv/bin/python -m build

## Testing
#####################################################################

.PHONY: test
test: lint unit-test ## Run all linters and tests.

.PHONY: unit-test
unit-test: $(REPO_ROOT)/.venv/.installed ## Run unit tests.
	@echo "Running unit tests..."
	$(REPO_ROOT)/.venv/bin/coverage run -m unittest discover .
	$(REPO_ROOT)/.venv/bin/coverage xml
	$(REPO_ROOT)/.venv/bin/coverage report -m

## Formatting
#####################################################################

.PHONY: format
format: json-format md-format py-format yaml-format ## Format all files

.PHONY: json-format
json-format: $(REPO_ROOT)/node_modules/.installed ## Format JSON files.
	@echo "Formatting JSON files..."
	loglevel="log"
	if [ -n "$(DEBUG_LOGGING)" ]; then
		loglevel="debug"
	fi
	files=$$(
		git ls-files --deduplicate \
			'*.json' \
			'*.json5' \
			| while IFS='' read -r f; do [ -f "$${f}" ] && echo "$${f}" || true; done
	)
	if [ "$${files}" == "" ]; then
		exit 0
	fi
	./node_modules/.bin/prettier \
		--log-level "$${loglevel}" \
		--no-error-on-unmatched-pattern \
		--write \
		$${files}

.PHONY: md-format
md-format: $(REPO_ROOT)/node_modules/.installed ## Format Markdown files.
	@echo "Formatting Markdown files..."
	loglevel="log"
	if [ -n "$(DEBUG_LOGGING)" ]; then
		loglevel="debug"
	fi
	files=$$(
		git ls-files --deduplicate \
			'*.md' \
			| while IFS='' read -r f; do [ -f "$${f}" ] && echo "$${f}" || true; done
	)
	if [ "$${files}" == "" ]; then
		exit 0
	fi
	# NOTE: prettier uses .editorconfig for tab-width. \
	./node_modules/.bin/prettier \
		--log-level "$${loglevel}" \
		--no-error-on-unmatched-pattern \
		--write \
		$${files}

.PHONY: py-format
py-format: $(AQUA_ROOT_DIR)/.installed ## Format Python files.
	@echo "Formatting Python files..."
	files=$$(
		git ls-files --deduplicate \
			'*.py' \
			| while IFS='' read -r f; do [ -f "$${f}" ] && echo "$${f}" || true; done
	)
	if [ "$${files}" == "" ]; then
		exit 0
	fi
	ruff check --select I --fix $${files}
	ruff format $${files}

.PHONY: yaml-format
yaml-format: $(REPO_ROOT)/node_modules/.installed ## Format YAML files.
	@echo "Formatting YAML files..."
	loglevel="log"
	if [ -n "$(DEBUG_LOGGING)" ]; then
		loglevel="debug"
	fi
	files=$$(
		git ls-files --deduplicate \
			'*.yml' \
			'*.yaml' \
	)
	if [ "$${files}" == "" ]; then
		exit 0
	fi
	./node_modules/.bin/prettier \
		--log-level "$${loglevel}" \
		--no-error-on-unmatched-pattern \
		--write \
		$${files}

## Linting
#####################################################################

.PHONY: lint
lint: actionlint checkmake commitlint fixme format-check markdownlint mypy renovate-config-validator ruff textlint yamllint zizmor ## Run all linters.

.PHONY: actionlint
actionlint: $(AQUA_ROOT_DIR)/.installed ## Runs the actionlint linter.
	@echo "Running actionlint..."
	files=$$(
		git ls-files --deduplicate \
			'.github/workflows/*.yml' \
			'.github/workflows/*.yaml' \
			| while IFS='' read -r f; do [ -f "$${f}" ] && echo "$${f}" || true; done
	)
	if [ "$${files}" == "" ]; then
		exit 0
	fi
	actionlint \
		-ignore 'SC2016:' \
		$${files}

.PHONY: checkmake
checkmake: $(AQUA_ROOT_DIR)/.installed ## Runs the checkmake linter.
	@echo "Running checkmake..."
	files=$$(
		git ls-files --deduplicate \
			'Makefile' \
			'GNUmakefile' \
			| while IFS='' read -r f; do [ -f "$${f}" ] && echo "$${f}" || true; done \
	)
	if [ "$${files}" == "" ]; then
		exit 0
	fi
	if [ "$(OUTPUT_FORMAT)" == "github" ]; then
		checkmake \
			--format '::error file={{.FileName}},line={{.LineNumber}}::{{.Rule}}: {{.Violation}}' \
			$${files}
	else
		checkmake $${files}
	fi

COMMITLINT_FROM_REF ?=
COMMITLINT_TO_REF ?=

.PHONY: commitlint
commitlint: $(REPO_ROOT)/node_modules/.installed ## Run commitlint linter.
	@echo "Running commitlint..."
	commitlint_from=$(COMMITLINT_FROM_REF)
	commitlint_to=$(COMMITLINT_TO_REF)
	if [ "$${commitlint_from}" == "" ]; then
		# Try to get the default branch without hitting the remote server
		if git symbolic-ref --short refs/remotes/origin/HEAD >/dev/null 2>&1; then
			commitlint_from=$$(git symbolic-ref --short refs/remotes/origin/HEAD)
		elif git show-ref refs/remotes/origin/master >/dev/null 2>&1; then
			commitlint_from="origin/master"
		else
			commitlint_from="origin/main"
		fi
	fi
	if [ "$${commitlint_to}" == "" ]; then
		# If upstream of HEAD is on the commitlint_from branch, then we will
		# lint the last commit by default.
		current_branch=$$(git rev-parse --abbrev-ref @{u})
		if [ "$${commitlint_from}" == "$${current_branch}" ]; then
			commitlint_from="HEAD~1"
		fi
		commitlint_to="HEAD"
	fi
	./node_modules/.bin/commitlint \
		--from "$${commitlint_from}" \
		--to "$${commitlint_to}" \
		--verbose \
		--strict

.PHONY: fixme
fixme: $(AQUA_ROOT_DIR)/.installed ## Check for outstanding FIXMEs.
	@echo "Checking for outstanding FIXMEs..."
	output="default"
	if [ "$(OUTPUT_FORMAT)" == "github" ]; then
		output="github"
	fi
	# NOTE: todos does not use `git ls-files` because many files might be
	# 		unsupported and generate an error if passed directly on the
	# 		command line.
	todos \
		--output "$${output}" \
		--todo-types="FIXME,Fixme,fixme,BUG,Bug,bug,XXX,COMBAK"

.PHONY: format-check
format-check: ## Check that files are properly formatted.
	@echo "Checking that files are properly formatted..."
	if [ -n "$$(git diff)" ]; then
		>&2 echo "The working directory is dirty. Please commit, stage, or stash changes and try again."
		exit 1
	fi
	$(MAKE) format
	$(MAKE) license-headers
	exit_code=0
	if [ -n "$$(git diff)" ]; then
		>&2 echo "Some files need to be formatted. Please run '$(MAKE) format' and try again."
		if [ "$(OUTPUT_FORMAT)" == "github" ]; then
			echo "::group::git diff"
		fi
		git --no-pager diff
		if [ "$(OUTPUT_FORMAT)" == "github" ]; then
			echo "::endgroup::"
		fi
		exit_code=1
	fi
	git restore .
	exit "$${exit_code}"

.PHONY: markdownlint
markdownlint: $(REPO_ROOT)/node_modules/.installed $(AQUA_ROOT_DIR)/.installed ## Runs the markdownlint linter.
	@echo "Running markdownlint..."
	# NOTE: Issue and PR templates are handled specially so we can disable
	# MD041/first-line-heading/first-line-h1 without adding an ugly html comment
	# at the top of the file.
	files=$$( \
		git ls-files --deduplicate \
			'*.md' \
			| while IFS='' read -r f; do [ -f "$${f}" ] && echo "$${f}" || true; done
	)
	if [ "$${files}" == "" ]; then
		exit 0
	fi
	./node_modules/.bin/markdownlint-cli2 $${files}

.PHONY: mypy
mypy: $(REPO_ROOT)/.venv/.installed ## Runs the mypy type checker.
	@echo "Running mypy..."
	files=$$(
		git ls-files --deduplicate \
			'*.py' \
			| while IFS='' read -r f; do [ -f "$${f}" ] && echo "$${f}" || true; done
	)
	if [ "$${files}" == "" ]; then
		exit 0
	fi
	${REPO_ROOT}/.venv/bin/mypy \
		--config-file mypy.ini \
		$${files}

.PHONY: renovate-config-validator
renovate-config-validator: $(REPO_ROOT)/node_modules/.installed ## Validate Renovate configuration.
	@echo "Validating Renovate configuration..."
	./node_modules/.bin/renovate-config-validator \
		--strict

.PHONY: ruff
ruff: $(AQUA_ROOT_DIR)/.installed ## Runs the ruff linter.
	@echo "Running ruff..."
	files=$$(
		git ls-files --deduplicate \
			'*.py' \
			| while IFS='' read -r f; do [ -f "$${f}" ] && echo "$${f}" || true; done
	)
	if [ "$${files}" == "" ]; then
		exit 0
	fi
	if [ "$(OUTPUT_FORMAT)" == "github" ]; then
		ruff check --output-format=github $${files}
	else
		ruff check $${files}
	fi

.PHONY: textlint
textlint: $(REPO_ROOT)/node_modules/.installed $(AQUA_ROOT_DIR)/.installed ## Runs the textlint linter.
	@echo "Running textlint..."
	files=$$(
		git ls-files --deduplicate \
			'*.md' \
			'*.txt' \
			':!:requirements*.txt' \
			| while IFS='' read -r f; do [ -f "$${f}" ] && echo "$${f}" || true; done
	)
	if [ "$${files}" == "" ]; then
		exit 0
	fi
	./node_modules/.bin/textlint $${files}

.PHONY: yamllint
yamllint: $(REPO_ROOT)/.venv/.installed ## Runs the yamllint linter.
	@echo "Running yamllint..."
	files=$$(
		git ls-files --deduplicate \
			'*.yml' \
			'*.yaml' \
			| while IFS='' read -r f; do [ -f "$${f}" ] && echo "$${f}" || true; done
	)
	if [ "$${files}" == "" ]; then
		exit 0
	fi
	format="standard"
	if [ "$(OUTPUT_FORMAT)" == "github" ]; then
		format="github"
	fi
	./.venv/bin/yamllint \
		--strict \
		--format "$${format}" \
		$${files}

.PHONY: zizmor
zizmor: $(REPO_ROOT)/.venv/.installed ## Runs the zizmor linter.
	@echo "Running zizmor..."
	# NOTE: On GitHub actions this outputs SARIF format to zizmor.sarif.json
	#       in addition to outputting errors to the terminal.
	files=$$(
		git ls-files --deduplicate \
			'.github/workflows/*.yml' \
			'.github/workflows/*.yaml' \
			| while IFS='' read -r f; do [ -f "$${f}" ] && echo "$${f}" || true; done
	)
	if [ "$${files}" == "" ]; then
		exit 0
	fi
	format="plain"
	if [ "$(OUTPUT_FORMAT)" == "github" ]; then
		./.venv/bin/zizmor \
			--quiet \
			--pedantic \
			--format sarif \
			$${files} > zizmor.sarif.json
		format="github"
	fi
	./.venv/bin/zizmor \
		--quiet \
		--pedantic \
		--format "$${format}" \
		$${files}

## Maintenance
#####################################################################

.PHONY: update-lockfiles
update-lockfiles: $(REPO_ROOT)/.aqua-checksums.json $(REPO_ROOT)/package-lock.json $(REPO_ROOT)/uv.lock ## Update lockfiles.

.PHONY: license-headers
license-headers: ## Update license headers.
	@echo "Updating license headers..."
	files=$$(
		git ls-files --deduplicate \
			'*.c' \
			'*.cpp' \
			'*.go' \
			'*.h' \
			'*.hpp' \
			'*.js' \
			'*.lua' \
			'*.py' \
			'*.rb' \
			'*.rs' \
			'*.yaml' \
			'*.yml' \
			'Makefile' \
			| while IFS='' read -r f; do [ -f "$${f}" ] && echo "$${f}" || true; done
	)
	name=$$(git config user.name || true)
	if [ "$${name}" == "" ]; then
		>&2 echo "git user.name is required."
		>&2 echo "Set it up using:"
		>&2 echo "git config user.name \"John Doe\""
		exit 1
	fi
	for filename in $${files}; do
		if ! ( head "$${filename}" | $(GREP) -iL "Copyright" > /dev/null ); then
			./third_party/mbrukman/autogen/autogen.sh \
				--in-place \
				--no-code \
				--no-tlc \
				--copyright "$${name}" \
				--license apache \
				"$${filename}"
		fi
	done

.PHONY: todos
todos: $(AQUA_ROOT_DIR)/.installed ## Print outstanding TODOs.
	@echo "Checking for outstanding TODOs..."
	output="default"
	if [ "$(OUTPUT_FORMAT)" == "github" ]; then
		output="github"
	fi
	# NOTE: todos does not use `git ls-files` because many files might be
	# 		unsupported and generate an error if passed directly on the command
	# 		line.
	todos \
		--output "$${output}" \
		--todo-types="TODO,Todo,todo,FIXME,Fixme,fixme,BUG,Bug,bug,XXX,COMBAK"

.PHONY: clean-node-modules
clean-node-modules:
	@echo "Cleaning up node_modules..."
	$(RM) -r node_modules

.PHONY: clean
clean: clean-node-modules ## Delete temporary files.
	@echo "Cleaning up temporary files..."
	$(RM) -r .bin
	$(RM) -r $(AQUA_ROOT_DIR)
	$(RM) -r .venv
	$(RM) -r .uv
	$(RM) *.sarif.json
	$(RM) -r dist/
	$(RM) -r *.egg-info/
	$(RM) -r .coverage
	$(RM) -r coverage.xml
	python -Bc "import pathlib; [p.unlink() for p in pathlib.Path('.').rglob('*.py[cod]')]"
	python -Bc "import pathlib; [p.rmdir() for p in pathlib.Path('.').rglob('__pycache__')]"
