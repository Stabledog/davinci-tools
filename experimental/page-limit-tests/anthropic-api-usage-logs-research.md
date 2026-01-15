# Anthropic API Usage Logs Research

**Date:** 2026-01-11  
**Context:** Investigation into programmatic access to Anthropic's usage/billing data visible in the web console

## Problem Statement

The Anthropic web console at https://platform.claude.com/workspaces/default/logs displays a detailed table of API requests including:
- Timestamp
- Request ID (e.g., `req_…PkaN9cw`)
- Model
- Input/Output token counts
- Request type (HTTP)
- Service tier
- **Elapsed time** (visible in UI but missing from copy/paste export)

**Question:** Can this table be pulled programmatically via API?

## Findings

### Admin API Exists ✅

Anthropic provides an **Admin API** separate from the inference API:
- Endpoint: `https://api.anthropic.com/v1/organizations/`
- Documentation: https://platform.claude.com/docs/en/api/admin
- Requires: `ANTHROPIC_ADMIN_API_KEY` (different from regular API keys)

### Available Endpoints

#### 1. Messages Usage Report
**Endpoint:** `GET /v1/organizations/usage_report/messages`  
**Docs:** https://platform.claude.com/docs/en/api/admin/usage_report/retrieve_messages

**Query Parameters:**
- `starting_at` (required): ISO 8601 timestamp
- `ending_at` (optional): ISO 8601 timestamp
- `bucket_width`: "1h" | "1d" | "1m" (aggregation interval)
- `group_by`: ["api_key_id", "workspace_id", "model", "context_window", "service_tier"]
- `api_key_ids`: Filter by specific keys
- `workspace_ids`: Filter by workspaces
- `models`: Filter by models
- `service_tiers`: ["standard", "batch", "priority", ...]
- `context_window`: ["0-200k", "200k-1M"]
- `limit`: Pagination limit
- `page`: Pagination cursor

**Returns:**
```json
{
  "data": [{
    "starting_at": "2025-08-01T00:00:00Z",
    "ending_at": "2025-08-02T00:00:00Z",
    "results": [{
      "api_key_id": "apikey_01...",
      "workspace_id": "wrkspc_01...",
      "model": "claude-sonnet-4-20250514",
      "service_tier": "standard",
      "context_window": "0-200k",
      "uncached_input_tokens": 1500,
      "cache_read_input_tokens": 200,
      "cache_creation": {
        "ephemeral_1h_input_tokens": 1000,
        "ephemeral_5m_input_tokens": 500
      },
      "output_tokens": 500,
      "server_tool_use": {
        "web_search_requests": 10
      }
    }]
  }],
  "has_more": true,
  "next_page": "2019-12-27T18:11:19.117Z"
}
```

#### 2. Cost Report
**Endpoint:** `GET /v1/organizations/cost_report`  
**Docs:** https://platform.claude.com/docs/en/api/admin/cost_report/retrieve

Returns aggregated cost data.

### What's Available ✅

- Input/output token counts
- Model identifiers
- Service tier classification
- API key ID
- Workspace ID
- Timestamp ranges
- Cache usage (creation/read tokens)
- Server tool use (e.g., web search counts)
- **Aggregated data** over time buckets

### What's NOT Available ❌

- **Individual request IDs** (`req_…`)
- **Elapsed time per request**
- **Real-time per-request logs**
- Request-level details (prompts, responses, errors)
- The granular table view from the console

## The Gap

**Console UI > API Capabilities**

The web console at `platform.claude.com/workspaces/default/logs` provides:
- Per-request granularity
- Request IDs for debugging
- Elapsed time (not in copy/paste export)
- Ability to drill into individual requests

The Admin API provides:
- **Aggregated statistics only**
- Time-bucketed data
- No per-request detail
- Suitable for billing/monitoring, not debugging

## Assessment

> **Conclusion:** You're correct that the admin API lags behind the inference API in terms of granularity. Individual request logs visible in the console are NOT exposed through the public API.

The Admin API is designed for:
- ✅ Billing reconciliation
- ✅ Usage monitoring over time
- ✅ Cost analysis by workspace/key
- ✅ Capacity planning

The Admin API is NOT designed for:
- ❌ Debugging specific requests
- ❌ Request-level auditing
- ❌ Performance analysis (elapsed time)
- ❌ Log correlation with external systems

## Practical Implications

1. **For billing analysis:** Use the Admin API with appropriate aggregation
2. **For debugging:** Must rely on console UI or implement client-side logging
3. **For performance metrics:** Track elapsed time client-side during API calls
4. **For audit trails:** Log request IDs client-side when making API calls

## Authentication Requirements

The Admin API uses a different authentication header:
```bash
curl https://api.anthropic.com/v1/organizations/usage_report/messages \
  -H "X-Api-Key: $ANTHROPIC_ADMIN_API_KEY"
```

Note: `ANTHROPIC_ADMIN_API_KEY` is distinct from regular API keys. Create these in [Account Settings](https://platform.claude.com/settings/keys).

## Future Considerations

If detailed request logs are needed:
1. Implement client-side request/response logging
2. Store request IDs with timestamps and elapsed times
3. Correlate with Admin API aggregated data for billing
4. Consider using the `request-id` response header for tracking

## References

- Admin API Overview: https://platform.claude.com/docs/en/api/admin
- Messages Usage Report: https://platform.claude.com/docs/en/api/admin/usage_report/retrieve_messages
- Cost Report: https://platform.claude.com/docs/en/api/admin/cost_report/retrieve
- Web Console Logs: https://platform.claude.com/workspaces/default/logs

## Related Files

- [anthropic-billing-page-jan-11.txt](anthropic-billing-page-jan-11.txt) - Copy/paste export from console (missing elapsed time)
