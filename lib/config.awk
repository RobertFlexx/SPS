# Read SPS config into caller-provided arrays. Repo lines are kept separately
# because there can be more than one.

function config_read(path, values, repo_name, repo_path, repo_priority,
		line, fields, n, key, rest, count) {
	count = 0
	while ((getline line < path) > 0) {
		line = sps_trim(line)
		if (line == "" || line ~ /^#/) continue
		n = split(line, fields, /[[:space:]]+/)
		key = fields[1]
		if (key == "repo") {
			if (n < 3 || n > 4) sps_error(path ": malformed repo declaration")
			count++
			repo_name[count] = fields[2]
			repo_path[count] = fields[3]
			repo_priority[count] = n == 4 ? fields[4] : 0
			continue
		}
		rest = line
		sub(/^[^[:space:]]+[[:space:]]+/, "", rest)
		values[key] = rest
	}
	close(path)
	return count
}

