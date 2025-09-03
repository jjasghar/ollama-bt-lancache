# Build stage
FROM golang:1.21-alpine AS builder

# Install build dependencies
RUN apk add --no-cache git ca-certificates tzdata

# Set working directory
WORKDIR /app

# Copy go mod files
COPY go.mod go.sum ./

# Download dependencies
RUN go mod download

# Copy source code
COPY server/ ./server/

# Build the application
RUN CGO_ENABLED=0 GOOS=linux go build -a -installsuffix cgo -o ollama-bt-lancache ./server

# Final stage
FROM alpine:latest

# Install runtime dependencies
RUN apk --no-cache add ca-certificates tzdata

# Create non-root user
RUN addgroup -g 1001 -S ollama && \
    adduser -u 1001 -S ollama -G ollama

# Set working directory
WORKDIR /app

# Copy binary from builder stage
COPY --from=builder /app/ollama-bt-lancache .

# Copy configuration template
COPY config.yaml.example ./config.yaml

# Change ownership to non-root user
RUN chown -R ollama:ollama /app

# Switch to non-root user
USER ollama

# Expose port
EXPOSE 8080

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD wget --no-verbose --tries=1 --spider http://localhost:8080/api/models || exit 1

# Run the application
CMD ["./ollama-bt-lancache"]
