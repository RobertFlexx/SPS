# Common POSIX AWK helpers. Keep BEGIN/END out of this file so callers can load
# it alongside the other modules in any order.

function sps_ltrim(s) { sub(/^[[:space:]]+/, "", s); return s }
function sps_rtrim(s) { sub(/[[:space:]]+$/, "", s); return s }
function sps_trim(s)  { return sps_rtrim(sps_ltrim(s)) }

function sps_error(message, status) {
	if (status == "") status = 1
	print (SPS_PROGRAM == "" ? "sps" : SPS_PROGRAM) ": " message > "/dev/stderr"
	exit status
}

function sps_valid_name(name) {
	return name ~ /^[A-Za-z0-9_+][A-Za-z0-9_+.-]*$/ && name !~ /\.\./
}

function sps_join(list, value, separator) {
	if (separator == "") separator = ","
	return list == "" ? value : list separator value
}

function sps_split_csv(value, output,    count, i, item, result) {
	for (i in output) delete output[i]
	if (value == "") return 0
	count = split(value, result, /,/)
	for (i = 1; i <= count; i++) {
		item = sps_trim(result[i])
		if (item != "") output[++output[0]] = item
	}
	return output[0]
}

function sps_tsv_safe(value) {
	return value !~ /[\t\r\n]/
}

