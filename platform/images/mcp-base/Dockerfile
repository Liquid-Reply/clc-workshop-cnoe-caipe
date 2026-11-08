# Base image for workshop MCP servers: Python + FastMCP. The server code is NOT baked in; it is mounted from a
# ConfigMap (apps/prometheus-mcp) so attendees change it with a Git commit, not an image build.
FROM docker.io/library/python:3.13-slim
RUN pip install --no-cache-dir "fastmcp>=2.12,<3" httpx
