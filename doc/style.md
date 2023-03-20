# Style Specification

## SystemVerilog Code

We use [lowRISC Verilog Coding Style Guide](https://github.com/lowRISC/style-guides/blob/master/VerilogCodingStyle.md) in this project. We mostly adopt its naming convention.

------

Following is a quick reference of the naming convention copied from the above link:

| Construct                                                    | Style                          |
| ------------------------------------------------------------ | ------------------------------ |
| Declarations (module, class, package, interface)             | `lower_snake_case`             |
| Instance names                                               | `lower_snake_case`             |
| Signals (nets and ports)                                     | `lower_snake_case`             |
| Variables, functions, tasks                                  | `lower_snake_case`             |
| Named code blocks                                            | `lower_snake_case`             |
| \`define macros                                              | `ALL_CAPS`                     |
| Tunable parameters for parameterized modules, classes, and interfaces | `UpperCamelCase`             |
| Constants                                                    | `ALL_CAPS` or `UpperCamelCase` |
| Enumeration types                                            | `lower_snake_case_e`           |
| Other typedef types                                          | `lower_snake_case_t`           |
| Enumerated value names                                       | `UpperCamelCase`               |

Please refer to the document for more detail.

## Git Commit Message

We use [Conventional Commits 1.0.0](https://www.conventionalcommits.org/en/v1.0.0/) in this project.

------

Following is a quick reference for the structure copied from the above link:

The commit message should be structured as follows:

```
<type>[optional scope]: <description>

[optional body]

[optional footer(s)]
```

The commit contains the following structural elements, to communicate intent to the consumers of your library:

1. **fix:** a commit of the *type* `fix` patches a bug in your codebase (this correlates with [`PATCH`](http://semver.org/#summary) in Semantic Versioning).
2. **feat:** a commit of the *type* `feat` introduces a new feature to the codebase (this correlates with [`MINOR`](http://semver.org/#summary) in Semantic Versioning).
3. **BREAKING CHANGE:** a commit that has a footer `BREAKING CHANGE:`, or appends a `!` after the type/scope, introduces a breaking API change (correlating with [`MAJOR`](http://semver.org/#summary) in Semantic Versioning). A BREAKING CHANGE can be part of commits of any *type*.
4. *types* other than `fix:` and `feat:` are allowed, for example [@commitlint/config-conventional](https://github.com/conventional-changelog/commitlint/tree/master/@commitlint/config-conventional) (based on the [the Angular convention](https://github.com/angular/angular/blob/22b96b9/CONTRIBUTING.md#-commit-message-guidelines)) recommends `build:`, `chore:`, `ci:`, `docs:`, `style:`, `refactor:`, `perf:`, `test:`, and others.
5. *footers* other than `BREAKING CHANGE: <description>` may be provided and follow a convention similar to [git trailer format](https://git-scm.com/docs/git-interpret-trailers).

Additional types are not mandated by the Conventional  Commits specification, and have no implicit effect in Semantic  Versioning (unless they include a BREAKING CHANGE). 

 A scope may be provided to a commit's type, to provide additional  contextual information and is contained within parenthesis, e.g., `feat(parser): add ability to parse arrays`.

------

Following is an explanation of various *types* copied from [here](https://github.com/angular/angular/blob/22b96b9/CONTRIBUTING.md#type):

- **build**: Changes that affect the build system or external dependencies (example scopes: gulp, broccoli, npm)
- **ci**: Changes to our CI configuration files and scripts (example scopes: Travis, Circle, BrowserStack, SauceLabs)
- **docs**: Documentation only changes
- **feat**: A new feature
- **fix**: A bug fix
- **perf**: A code change that improves performance
- **refactor**: A code change that neither fixes a bug nor adds a feature
- **style**: Changes that do not affect the meaning of the code (white-space, formatting, missing semi-colons, etc)
- **test**: Adding missing tests or correcting existing tests
