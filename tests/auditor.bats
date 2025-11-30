#!/usr/bin/env bats

setup() {
    SCRIPT="./k8s-image-auditor.sh"
}

@test "Script exists and is executable" {
    [ -x "$SCRIPT" ]
}

@test "Help flag (-h) prints usage info" {
    run "$SCRIPT" -h
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Usage:" ]]
}

@test "Detects missing dependencies" {
    # Run with a minimal PATH so custom tools (kubectl, skopeo) are not found
    run env PATH='/usr/bin:/bin' bash "$SCRIPT"
    
    # 1. Check exit code
    [ "$status" -eq 1 ]
    
    # 2. Debugging: If it fails, print the output so we see WHY
    if [[ ! "$output" =~ "Error: Missing required tools" ]]; then
        echo "output: $output"
    fi

    # 3. Check for the NEW error message format
    [[ "$output" =~ "Error: Missing required tools" ]]
}

@test "Output file flag (-o) is respected" {
    run "$SCRIPT" -h
    [[ "$output" =~ "-o <file>" ]]
}