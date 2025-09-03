# Build stage
FROM golang:1.21-alpine AS builder

# Install build dependencies
RUN apk add --no-cache git ca-certificates

# Set working directory
WORKDIR /app

# Clone privtracker repository
RUN git clone https://github.com/meehow/privtracker.git .

# Build the tracker
RUN CGO_ENABLED=0 GOOS=linux go build -a -installsuffix cgo -o tracker .

# Final stage
FROM alpine:latest

# Install runtime dependencies
RUN apk --no-cache add ca-certificates

# Create non-root user
RUN addgroup -g 1001 -S tracker && \
    adduser -u 1001 -S tracker -G tracker

# Set working directory
WORKDIR /app

# Copy binary from builder stage
COPY --from=builder /app/tracker .

# Change ownership to non-root user
RUN chown -R tracker:tracker /app

# Switch to non-root user
USER tracker

# Expose port
EXPOSE 8080

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD wget --no-verbose --tries=1 --spider http://localhost:8080 || exit 1

# Run the tracker
CMD ["./tracker"]
