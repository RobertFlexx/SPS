# Checks and small transformations for the SPS text database.

BEGIN {
    FS = sprintf("%c", 9)
    OFS = FS
    sps_errors = 0
    sps_stderr = "cat >&2"
}

function sps_diag(message) {
    print (sps_program != "" ? sps_program ": " : "") message | sps_stderr
    sps_errors++
}

function sps_valid_name(value) {
    return value ~ /^[ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789][ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+_.-]*$/
}

function sps_valid_path(path,    count, pieces, i) {
    if (path == "" || path ~ /[[:cntrl:]]/ || path ~ /^\// ||
        path ~ /^\.\// || path ~ /\/\// || path ~ /\/$/)
        return 0
    count = split(path, pieces, "/")
    for (i = 1; i <= count; i++)
        if (pieces[i] == "" || pieces[i] == "." || pieces[i] == "..")
            return 0
    return 1
}

sps_action == "owners-remove" || sps_action == "owners-validate" ||
sps_action == "owners-query" {
    if (NF != 2 || !sps_valid_path($1) || !sps_valid_name($2)) {
        sps_diag("malformed owner record at line " FNR)
        next
    }
    if (sps_owner_seen[$1]++) {
        sps_diag("duplicate owner record for '" $1 "'")
        next
    }
    if (sps_action == "owners-remove" && $2 != sps_package)
        print $1, $2
    else if (sps_action == "owners-query" && $1 == sps_path)
        print $2
    next
}

sps_action == "world-remove" || sps_action == "world-validate" {
    if (NF != 1 || !sps_valid_name($1)) {
        sps_diag("malformed world record at line " FNR)
        next
    }
    if (sps_world_seen[$1]++) {
        sps_diag("duplicate world record for '" $1 "'")
        next
    }
    if (sps_action == "world-remove" && $1 != sps_package)
        print $1
    next
}

END {
    if (sps_action != "" && sps_action != "owners-remove" &&
             sps_action != "owners-validate" &&
             sps_action != "owners-query" &&
             sps_action != "world-remove" &&
             sps_action != "world-validate")
        sps_diag("unknown database action '" sps_action "'")
    close(sps_stderr)
    if (sps_errors)
        exit 1
}
