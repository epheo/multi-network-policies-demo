#!/bin/bash

set -e

NAMESPACE="multi-network-demo"
VM_NAME="fedora-dual-nic-vm"

echo "======================================================="
echo "Multi-Network Policies Demo - SSH Access Control Tests"
echo "======================================================="

function wait_for_vm() {
    echo "Waiting for VM to be ready..."
    kubectl wait --for=condition=Ready vmi/$VM_NAME -n $NAMESPACE --timeout=300s
    echo "VM is ready!"
}

function get_vm_ips() {
    echo "Getting VM IP addresses..."
    VM_POD_IP=$(kubectl get vmi $VM_NAME -n $NAMESPACE -o jsonpath='{.status.interfaces[0].ipAddress}')
    VM_BR_EX_IP=$(kubectl get vmi $VM_NAME -n $NAMESPACE -o jsonpath='{.status.interfaces[1].ipAddress}')
    
    echo "VM Pod Network IP: $VM_POD_IP"
    echo "VM br-ex Network IP: $VM_BR_EX_IP"
}

function test_baseline_connectivity() {
    echo ""
    echo "=== Baseline SSH Connectivity Tests (Before Network Policies) ==="
    
    echo "Testing SSH to Pod Network IP:"
    kubectl exec -n $NAMESPACE test-client-pod -- timeout 5 nc -zv $VM_POD_IP 22 || echo "SSH connectivity test to Pod Network"
    
    echo "Testing SSH to br-ex Network IP:"
    kubectl exec -n $NAMESPACE test-client-dual-nic -- timeout 5 nc -zv $VM_BR_EX_IP 22 || echo "SSH connectivity test to br-ex Network"
    
    echo "Testing HTTP connectivity (should work):"
    kubectl exec -n $NAMESPACE test-client-pod -- timeout 5 nc -zv $VM_POD_IP 80 || echo "HTTP connectivity test"
}

function apply_ssh_control_policies() {
    echo ""
    echo "=== Applying SSH Access Control Policies ==="
    kubectl apply -f network-policies/ssh-access-control-policy.yaml
    echo "Waiting for policies to take effect..."
    sleep 15
}

function test_ssh_access_control() {
    echo ""
    echo "=== Testing SSH Access Control Enforcement ==="
    
    echo "Testing SSH from authorized test-client to Pod Network (should work):"
    kubectl exec -n $NAMESPACE test-client-pod -- timeout 10 nc -zv $VM_POD_IP 22 && echo "SUCCESS: SSH allowed on Pod Network" || echo "BLOCKED: SSH denied on Pod Network"
    
    echo "Testing SSH from test-client to br-ex Network (should be blocked):"
    kubectl exec -n $NAMESPACE test-client-dual-nic -- timeout 10 nc -zv $VM_BR_EX_IP 22 && echo "UNEXPECTED: SSH worked on br-ex" || echo "SUCCESS: SSH blocked on br-ex Network"
    
    echo "Testing HTTP access (should still work):"
    kubectl exec -n $NAMESPACE test-client-pod -- timeout 5 nc -zv $VM_POD_IP 80 && echo "SUCCESS: HTTP allowed" || echo "HTTP connectivity test"
    
    echo "Testing DNS resolution (should work on both networks):"
    kubectl exec -n $NAMESPACE test-client-pod -- timeout 5 nc -zv 8.8.8.8 53 && echo "SUCCESS: DNS works" || echo "DNS connectivity test"
}

function apply_network_policies() {
    echo ""
    echo "=== Applying All Network Policies ==="
    kubectl apply -f network-policies/pod-network-policy.yaml
    kubectl apply -f network-policies/br-ex-network-policy.yaml
    echo "Waiting for all policies to take effect..."
    sleep 15
}

function test_full_network_policies() {
    echo ""
    echo "=== Testing Full Network Policy Enforcement ==="
    
    echo "Testing SSH from authorized client to Pod Network (should work):"
    kubectl exec -n $NAMESPACE test-client-pod -- timeout 10 nc -zv $VM_POD_IP 22 && echo "SUCCESS: Authorized SSH works" || echo "ISSUE: Authorized SSH blocked"
    
    echo "Testing SSH from dual-nic client to br-ex Network (should be blocked):"
    kubectl exec -n $NAMESPACE test-client-dual-nic -- timeout 10 nc -zv $VM_BR_EX_IP 22 && echo "ISSUE: SSH leaked through" || echo "SUCCESS: SSH properly blocked"
    
    echo "Testing basic connectivity to ensure policies don't break essential services:"
    kubectl exec -n $NAMESPACE test-client-pod -- timeout 5 nc -zv 8.8.8.8 53 && echo "SUCCESS: DNS works" || echo "ISSUE: DNS blocked"
}

function show_policy_status() {
    echo ""
    echo "=== Network Policy Status ==="
    echo "Standard NetworkPolicies:"
    kubectl get networkpolicy -n $NAMESPACE
    echo ""
    echo "MultiNetworkPolicies:"
    kubectl get multinetworkpolicy -n $NAMESPACE 2>/dev/null || echo "No MultiNetworkPolicies found"
    echo ""
    echo "VM Network Interfaces:"
    kubectl get vmi $VM_NAME -n $NAMESPACE -o jsonpath='{.status.interfaces}' | jq '.' || echo "VM interface info not available"
}

function demonstrate_network_segmentation() {
    echo ""
    echo "=== Network Segmentation Demonstration ==="
    echo "This demo shows how the same VM with multiple NICs can have:"
    echo "• SSH access allowed on Pod Network (NIC 1)"
    echo "• SSH access blocked on br-ex Network (NIC 2)" 
    echo "• Different security policies per network interface"
    echo ""
    echo "This enables:"
    echo "• Management access via secure network"
    echo "• Production traffic via restricted network" 
    echo "• Service-specific access control"
}

function cleanup() {
    echo ""
    echo "=== Cleanup Options ==="
    read -p "Do you want to cleanup the policies? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        kubectl delete -f network-policies/ --ignore-not-found=true
        echo "Policies cleaned up!"
        echo "SSH access restored on both networks."
    else
        echo "Policies remain in place for further testing."
    fi
}

# Main execution
wait_for_vm
get_vm_ips
test_baseline_connectivity
apply_ssh_control_policies
test_ssh_access_control
apply_network_policies
test_full_network_policies
show_policy_status
demonstrate_network_segmentation
cleanup

echo ""
echo "=========================================="
echo "SSH Access Control Demo completed!"
echo "Check the results above to see how SSH"
echo "access was controlled per network interface."
echo "=========================================="