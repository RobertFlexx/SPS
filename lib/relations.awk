# Reverse dependency and path queries. These only need package names, not
# version constraint evaluation.

function rel_err(msg,    c) {
    c = "cat >&2"
    print (program == "" ? "sget" : program) ": " msg | c
    close(c)
    failed = 1
}

function rel_dep_name(spec,    p) {
    gsub(/^[ \t]+|[ \t]+$/, "", spec)
    p = match(spec, />=|<=|=|>|</)
    if (p) spec = substr(spec, 1, RSTART - 1)
    return spec
}

function rel_add_edges(pkg, list,    n, a, i, d) {
    if (list == "") return
    n = split(list, a, /,/)
    for (i = 1; i <= n; i++) {
        d = rel_dep_name(a[i])
        if (d != "") edge[pkg SUBSEP d] = 1
    }
}

function rel_sort(a, n,    gap,i,j,x) {
    gap=int(n/2)
    while (gap>0) {
        for (i=gap+1;i<=n;i++) {
            x=a[i]; j=i
            while (j>gap && a[j-gap]>x) { a[j]=a[j-gap]; j-=gap }
            a[j]=x
        }
        gap=int(gap/2)
    }
}

function rel_find(cur, target,    k,p,d) {
    if (cur == target) return 1
    seen[cur]=1
    for (k in edge) {
        split(k,p,SUBSEP)
        if (p[1] != cur) continue
        d=p[2]
        if (seen[d]) continue
        parent[d]=cur
        if (rel_find(d,target)) return 1
    }
    return 0
}

BEGIN { FS=OFS="\t" }
/^$/ { next }
{
    if (NF != 12) { rel_err(FILENAME ":" FNR ": malformed index record"); next }
    name=$1; prio=$9+0
    if (!(name in selected) || prio > priority[name]) {
        selected[name]=1
        priority[name]=prio
        runtime[name]=$5
        build[name]=$6
    }
}
END {
    if (failed) exit 2
    for (pkg in selected) {
        rel_add_edges(pkg, runtime[pkg])
        if (include_build+0) rel_add_edges(pkg, build[pkg])
    }

    if (action == "dependees") {
        if (!(query in selected)) { rel_err("package '" query "' not found"); exit 3 }
        n=0
        for (k in edge) {
            split(k,p,SUBSEP)
            if (p[2] == query && !out[p[1]]++) names[++n]=p[1]
        }
        rel_sort(names,n)
        for (i=1;i<=n;i++) print names[i]
    } else if (action == "why") {
        if (!(root in selected)) { rel_err("package '" root "' not found"); exit 3 }
        if (!(query in selected)) { rel_err("package '" query "' not found"); exit 3 }
        if (!rel_find(root,query)) {
            rel_err("'" root "' does not depend on '" query "'")
            exit 5
        }
        n=0; cur=query; path[++n]=cur
        while (cur != root) { cur=parent[cur]; path[++n]=cur }
        for (i=n;i>=1;i--) print path[i]
    } else {
        rel_err("unknown relation action '" action "'")
        exit 2
    }
}
