default: test

# Run the test suite
test:
    sh tests/test.sh

# Run tests with verbose output
test-verbose:
    VERBOSE=1 sh tests/test.sh

# Install to ~/.local/bin
install:
    ./install.sh

# Lint with shellcheck
lint:
    shellcheck bin/gitop bin/gitc install.sh tests/test.sh

# Run lint then tests
check: lint test
