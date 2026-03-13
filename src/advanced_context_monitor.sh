#!/bin/bash

# Advanced Context Monitor for Claude Session Manager
# Leverages OpenClaw 2026.3.12 context management improvements
# Author: Shikamaru <shikamarunaraclaw@gmail.com>

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONTEXT_LOG="/tmp/claude_context_monitor.log"
CONFIG_FILE="${HOME}/.config/claude-session-manager/config"

# OpenClaw 2026.3.12 context tracking
CONTEXT_TRACKING_ENABLED="${CONTEXT_TRACKING_ENABLED:-true}"
MAX_CONTEXT_SIZE="${MAX_CONTEXT_SIZE:-200000}"  # 200K tokens (for 1M context models)
CONTEXT_WARNING_THRESHOLD="${CONTEXT_WARNING_THRESHOLD:-150000}"  # 150K tokens

# Load configuration
if [[ -f "$CONFIG_FILE" ]]; then
    source "$CONFIG_FILE"
fi

# Enhanced context monitoring with 2026.3.12 features
monitor_context_usage() {
    local session_name="$1"
    
    if [[ -z "$session_name" ]]; then
        echo "Usage: monitor_context_usage <session_name>"
        return 1
    fi
    
    # Check if session exists
    if ! tmux list-sessions -F "#{session_name}" | grep -q "^$session_name$"; then
        return 1
    fi
    
    # Capture session content for analysis
    local panes=$(tmux list-panes -t "$session_name" -a -F "#{pane_id}")
    local total_content=""
    local estimated_tokens=0
    
    for pane in $panes; do
        # Capture full scrollback history
        local pane_content=$(tmux capture-pane -t "$pane" -p -S -2000 2>/dev/null || true)
        total_content+="$pane_content"$'\n'
    done
    
    # Estimate token count (rough approximation: 1 token ≈ 4 characters)
    local char_count=${#total_content}
    estimated_tokens=$((char_count / 4))
    
    # Context analysis
    local context_percentage=$((estimated_tokens * 100 / MAX_CONTEXT_SIZE))
    local status="normal"
    
    if [[ $estimated_tokens -gt $CONTEXT_WARNING_THRESHOLD ]]; then
        if [[ $estimated_tokens -gt $MAX_CONTEXT_SIZE ]]; then
            status="critical"
        else
            status="warning"
        fi
    fi
    
    # Log context metrics
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] Session: $session_name, Tokens: ~$estimated_tokens, Status: $status, Percentage: ${context_percentage}%" >> "$CONTEXT_LOG"
    
    # Output current status
    echo "Context Monitor: $session_name"
    echo "  Estimated tokens: ~$estimated_tokens"
    echo "  Context usage: ${context_percentage}%"
    echo "  Status: $status"
    
    # Return status code based on usage
    case "$status" in
        "critical") return 2 ;;
        "warning") return 1 ;;
        "normal") return 0 ;;
    esac
}

# Enhanced session context analysis
analyze_session_context_patterns() {
    local session_name="$1"
    local hours_back="${2:-4}"
    
    if [[ ! -f "$CONTEXT_LOG" ]]; then
        echo "No context monitoring data available"
        return 1
    fi
    
    local cutoff_time=$(date -d "$hours_back hours ago" '+%Y-%m-%d %H:%M:%S')
    
    echo "Context Analysis for $session_name (last ${hours_back}h):"
    echo "================================================="
    
    # Extract relevant data for this session
    local session_data=$(grep "Session: $session_name" "$CONTEXT_LOG" | \
                        awk -v cutoff="$cutoff_time" '$0 >= cutoff')
    
    if [[ -z "$session_data" ]]; then
        echo "No recent context data for $session_name"
        return 1
    fi
    
    # Calculate context statistics
    echo "$session_data" | awk '
    BEGIN { 
        count=0; token_total=0; max_tokens=0; min_tokens=999999
        warning_count=0; critical_count=0
    }
    /Tokens:/ { 
        gsub(/[^0-9]/, "", $6); 
        tokens = $6
        token_total += tokens
        if (tokens > max_tokens) max_tokens = tokens
        if (tokens < min_tokens) min_tokens = tokens
        count++
        
        if ($8 == "warning") warning_count++
        if ($8 == "critical") critical_count++
    }
    END { 
        if (count > 0) {
            printf "  Data points: %d\n", count
            printf "  Average tokens: %.0f\n", token_total/count
            printf "  Peak tokens: %d\n", max_tokens
            printf "  Min tokens: %d\n", min_tokens
            printf "  Warning states: %d (%.1f%%)\n", warning_count, warning_count*100/count
            printf "  Critical states: %d (%.1f%%)\n", critical_count, critical_count*100/count
            
            if (critical_count > 0) {
                print "  🚨 Context management attention needed!"
            } else if (warning_count > count*0.3) {
                print "  ⚠️  Consider context pruning optimization"
            } else {
                print "  ✅ Context usage within healthy ranges"
            }
        }
    }'
}

# Context optimization suggestions based on OpenClaw 2026.3.12
suggest_context_optimizations() {
    local session_name="$1"
    
    # Check current context status
    local context_status=$(monitor_context_usage "$session_name")
    local exit_code=$?
    
    echo ""
    echo "OpenClaw 2026.3.12 Context Optimization Suggestions:"
    echo "=================================================="
    
    case $exit_code in
        0)  # Normal
            echo "✅ Context usage is healthy"
            echo "💡 Consider enabling automatic context pruning for long sessions"
            ;;
        1)  # Warning
            echo "⚠️  Context approaching limits"
            echo "🔧 Suggested actions:"
            echo "   • Enable context pruning with 'keepLastAssistants: 3'"
            echo "   • Use soft trimming to preserve recent context"
            echo "   • Consider session restart if context becomes unwieldy"
            ;;
        2)  # Critical
            echo "🚨 Context usage critical!"
            echo "🔧 Immediate actions needed:"
            echo "   • Enable hard context clearing"
            echo "   • Restart session to reset context"
            echo "   • Implement automated context pruning"
            echo "   • Review session history for optimization opportunities"
            ;;
    esac
    
    echo ""
    echo "OpenClaw 2026.3.12 Features Available:"
    echo "• Advanced context pruning with TTL management"
    echo "• Tool output preservation settings"
    echo "• Graduated pruning levels (soft → hard)"
    echo "• Context health monitoring and alerts"
}

# Monitor all Claude sessions for context health
monitor_all_claude_sessions() {
    echo "🔍 Monitoring all Claude Code sessions for context health..."
    echo ""
    
    # Get all Claude sessions
    local claude_sessions=$("$SCRIPT_DIR/claude_session_detector.sh" detect 2>/dev/null || echo "")
    
    if [[ -z "$claude_sessions" ]]; then
        echo "No Claude Code sessions detected"
        return 0
    fi
    
    local warning_sessions=()
    local critical_sessions=()
    
    while IFS='|' read -r session status activity; do
        if [[ -n "$session" ]]; then
            echo "Checking $session..."
            monitor_context_usage "$session" >/dev/null
            local exit_code=$?
            
            case $exit_code in
                1) warning_sessions+=("$session") ;;
                2) critical_sessions+=("$session") ;;
            esac
        fi
    done <<< "$claude_sessions"
    
    # Summary report
    echo ""
    echo "📊 Context Health Summary:"
    echo "========================"
    
    if [[ ${#critical_sessions[@]} -gt 0 ]]; then
        echo "🚨 CRITICAL sessions: ${critical_sessions[*]}"
        echo "   → Immediate attention required!"
    fi
    
    if [[ ${#warning_sessions[@]} -gt 0 ]]; then
        echo "⚠️  WARNING sessions: ${warning_sessions[*]}"
        echo "   → Consider context optimization"
    fi
    
    local total_sessions=$(echo "$claude_sessions" | wc -l)
    local healthy_sessions=$((total_sessions - ${#warning_sessions[@]} - ${#critical_sessions[@]}))
    
    echo "✅ Healthy sessions: $healthy_sessions"
    echo ""
    
    if [[ ${#critical_sessions[@]} -gt 0 || ${#warning_sessions[@]} -gt 0 ]]; then
        echo "Run with 'suggest' option for optimization recommendations"
    fi
}

# Cleanup old context logs
cleanup_context_logs() {
    if [[ -f "$CONTEXT_LOG" ]]; then
        local cutoff_time=$(date -d "7 days ago" '+%Y-%m-%d %H:%M:%S')
        local temp_file=$(mktemp)
        
        awk -v cutoff="$cutoff_time" '$0 >= cutoff' "$CONTEXT_LOG" > "$temp_file"
        mv "$temp_file" "$CONTEXT_LOG"
        
        echo "Context logs cleaned (kept last 7 days)"
    fi
}

# Main function
main() {
    case "${1:-help}" in
        "monitor")
            if [[ -n "$2" ]]; then
                monitor_context_usage "$2"
            else
                monitor_all_claude_sessions
            fi
            ;;
        "analyze")
            analyze_session_context_patterns "$2" "$3"
            ;;
        "suggest")
            suggest_context_optimizations "$2"
            ;;
        "cleanup")
            cleanup_context_logs
            ;;
        "help"|*)
            echo "Advanced Context Monitor for Claude Session Manager (OpenClaw 2026.3.12)"
            echo ""
            echo "Usage: $0 <command> [args]"
            echo ""
            echo "Commands:"
            echo "  monitor [session]    Monitor context usage (all sessions if no session specified)"
            echo "  analyze <session> [h] Analyze context patterns (default: 4h)"
            echo "  suggest <session>    Get optimization suggestions"
            echo "  cleanup             Clean old context logs"
            echo ""
            echo "OpenClaw 2026.3.12 Features:"
            echo "• Advanced context pruning with TTL management"
            echo "• Intelligent tool output preservation"
            echo "• Graduated context clearing (soft → hard)"
            echo "• Real-time context health monitoring"
            echo ""
            exit 1
            ;;
    esac
}

# Run main function
main "$@"