#pragma once

#include <algorithm>
#include <atomic>
#include <cstddef>
#include <cstring>
#include <vector>

namespace sa {

class FrameRing {
public:
    explicit FrameRing(size_t frames)
        : cap_(roundUpPowerOf2(frames)),
          mask_(cap_ - 1),
          buf_(cap_ * 2) {}

    size_t available() const { return w_.load(std::memory_order_acquire) - r_.load(std::memory_order_acquire); }

    size_t push(const float* src, size_t frames) {
        const size_t w = w_.load(std::memory_order_relaxed);
        const size_t free = cap_ - (w - r_.load(std::memory_order_acquire));
        const size_t n = frames < free ? frames : free;
        if (n == 0) return 0;

        const size_t slot = w & mask_;
        const size_t first = std::min(n, cap_ - slot);
        const size_t second = n - first;

        if (src) {
            std::memcpy(&buf_[2 * slot], src, first * 2 * sizeof(float));
            if (second > 0) {
                std::memcpy(&buf_[0], src + 2 * first, second * 2 * sizeof(float));
            }
        } else {
            std::memset(&buf_[2 * slot], 0, first * 2 * sizeof(float));
            if (second > 0) {
                std::memset(&buf_[0], 0, second * 2 * sizeof(float));
            }
        }

        w_.store(w + n, std::memory_order_release);
        return n;
    }

    size_t pop(float* dst, size_t frames) {
        const size_t r = r_.load(std::memory_order_relaxed);
        const size_t have = w_.load(std::memory_order_acquire) - r;
        const size_t n = frames < have ? frames : have;
        if (n == 0) return 0;

        const size_t slot = r & mask_;
        const size_t first = std::min(n, cap_ - slot);
        const size_t second = n - first;

        if (dst) {
            std::memcpy(dst, &buf_[2 * slot], first * 2 * sizeof(float));
            if (second > 0) {
                std::memcpy(dst + 2 * first, &buf_[0], second * 2 * sizeof(float));
            }
        }

        r_.store(r + n, std::memory_order_release);
        return n;
    }

    // Reader side only: drops the oldest frames so that at most `keep` remain.
    void trim(size_t keep) {
        const size_t r = r_.load(std::memory_order_relaxed);
        const size_t have = w_.load(std::memory_order_acquire) - r;
        if (have > keep) r_.store(r + (have - keep), std::memory_order_release);
    }

    // Called on stream reset. Thread-safe when the reader stream is destroyed first.
    void clear() { r_.store(w_.load(std::memory_order_acquire), std::memory_order_release); }

private:
    static size_t roundUpPowerOf2(size_t v) {
        if (v == 0) return 1;
        --v;
        v |= v >> 1;
        v |= v >> 2;
        v |= v >> 4;
        v |= v >> 8;
        v |= v >> 16;
        if constexpr (sizeof(size_t) > 4) v |= v >> 32;
        return v + 1;
    }

    size_t cap_;
    size_t mask_;
    std::vector<float> buf_;
    std::atomic<size_t> r_{0}, w_{0};
};

}
