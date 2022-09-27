# splits aggregated error messages into their parts
def splitMsg: if test("KNV2009: \\d+ errors:") then (split("\n") | .[1:-3] | .[]) else . end;

# simplifies messages
def mapMsg(s; t): s as $s | t as $t | if contains($s) then $t else . end;
def mapMsg(s): mapMsg(s; s);

# these should hopefully all go away once our API server is healthy enough
def apiDiscoveryFailed: mapMsg("API discovery failed");
def apiDiscoveryConsequence:
    mapMsg("no matches for kind"; "API discovery error consequence")
  | mapMsg("unknown resource type"; "API discovery error consequence");
def clientTimeout:
    mapMsg("Client.Timeout"; "client timeout")
  | mapMsg("the server was unable to return a response in the time allotted"; "client timeout");
def serverTimeout: mapMsg("context deadline exceeded"; "server timeout");

# not sure what this is; hoping it will be more clear once API server-related errors are gone
def dependencyFailed: mapMsg("dependency apply actuation failed"; "dependency failed");

# these are a bit weird; the error message contains the string %!w(<nil>) which looks like a go fmt string
# for printing an error, but the error is nil. unclear what's going on.
def failedToApply:
  if contains("failed to apply") and contains("%!w(<nil>)")
  then capture("failed to apply (?<kind>.+),") | "failed to apply: \(.kind)"
  else .
  end;

# i did see some access denied errors for the same kinds before, but now i don't ¯\_(ツ)_/¯
def accessDenied:
  mapMsg("access denied")
  | if contains("forbidden")
  then
    capture("resource \\\"(?<kind>.+?)\\\" in API group \\\"(?<group>.*?)\\\"")
    | if .group != "" then "forbidden: \(.kind).\(.group)" else "forbidden: \(.kind)" end
  else .
  end;


# these should disappear when all repo syncs use OCI!
def gitHungUp: mapMsg("the remote end hung up unexpectedly"; "git hung up");

# these we need to fix
def conflict:
    mapMsg("cannot manage resources declared in another repository"; "conflict")
  | mapMsg("detects a management conflict"; "conflict");
def kustomizeBuildFailed: mapMsg("failed to run kustomize build");


# when a user removes a namespace, we apparently don't clean up the syncs properly
def missingNamespaceFolder:
  if contains("namespaces/gcp-projects") and contains("no such file or directory")
  then "namespace removed"
  else .
  end;

# https://partnerissuetracker.corp.google.com/issues/248346343
def resourceVersionSet: mapMsg("resourceVersion should not be set"; "inventory/resourceVersion");

# this puts all of the above functions together to classify each error message
def mapError: (
  splitMsg
  | accessDenied
  | missingNamespaceFolder
  | dependencyFailed
  | kustomizeBuildFailed
  | conflict
  | gitHungUp
  | failedToApply
  | resourceVersionSet
  | apiDiscoveryConsequence
  | apiDiscoveryFailed
  | serverTimeout
  | clientTimeout
);

# this counts errors from a single sync, by the classification from mapError
# the output is, for each sync, an object on the form
# {
#   source: {"error-type": count, "error-type": count, ...},
#   sync: {"error-type": count, "error-type": count, ...},
#   rendering: {"error-type": count, "error-type": count, ...},
# }
def getErrors(f): (
  ((f | .errors) // [])
  | map(.errorMessage | mapError)
  | group_by(.) 
  | map({key: .[0], value: length}) | from_entries
);

# collect errors from all syncs into a single count object
def collectErrors(f):
  map(f)
  | reduce .[] as $entry (
    {};
    [., $entry]
    | map(to_entries)
    | flatten
    | group_by(.key)
    | map({(.[0].key): (map(.value) | add)}
    )
    | add // {}
  );


# this can be applied to the results of a single kubectl get -o json call
def classify:
  map({
    rendering: getErrors(.status.rendering),
    source: getErrors(.status.source),
    sync: getErrors(.status.sync),
  })
  | {
    source: collectErrors(.source),
    sync: collectErrors(.sync),
    rendering: collectErrors(.rendering)
  };

.items | classify
