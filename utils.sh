validate_commands() {
	local missing_counter=0
	for cmd in "$@"; do
		if ! command -v "$cmd" >/dev/null 2>&1; then
			echo "Error: El comando '$cmd' no está instalado." >&2
			((missing_counter++))
		fi
	done
	[ "$missing_counter" -eq 0 ]
}

# Dependencias
REQUIRED_TOOLS=("px" "kustomize" "mkcert")
