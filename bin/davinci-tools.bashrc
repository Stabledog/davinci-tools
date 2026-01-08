# davinci-tools.bashrc - Shell environment setup for davinci-tools
# Source this file in your shell or add it to your ~/.bashrc:
#   source /path/to/davinci-tools/bin/davinci-tools.bashrc

# Determine the bin directory (works even if sourced)
_DAVINCI_TOOLS_BIN="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Add to PATH if not already present
if [[ ":${PATH}:" != *":${_DAVINCI_TOOLS_BIN}:"* ]]; then
    export PATH="${_DAVINCI_TOOLS_BIN}:${PATH}"
fi

# Clean up temporary variable
unset _DAVINCI_TOOLS_BIN
