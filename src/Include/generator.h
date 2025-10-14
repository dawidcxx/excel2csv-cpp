#pragma once

#include <coroutine>
#include <iterator>
#include <exception>

template<typename T>
class generator {
public:
    struct promise_type {
        T current_value;
        
        generator get_return_object() {
            return generator{std::coroutine_handle<promise_type>::from_promise(*this)};
        }
        
        std::suspend_always initial_suspend() { return {}; }
        std::suspend_always final_suspend() noexcept { return {}; }
        
        std::suspend_always yield_value(T value) {
            current_value = std::move(value);
            return {};
        }
        
        void return_void() {}
        void unhandled_exception() { std::rethrow_exception(std::current_exception()); }
    };

    class iterator {
    public:
        using iterator_category = std::input_iterator_tag;
        using value_type = T;
        using difference_type = std::ptrdiff_t;
        using pointer = T*;
        using reference = T&;

        iterator() = default;
        
        explicit iterator(std::coroutine_handle<promise_type> h) : coro_handle(h) {
            if (coro_handle) {
                advance();
            }
        }

        iterator& operator++() {
            advance();
            return *this;
        }
        
        void operator++(int) { ++(*this); }

        const T& operator*() const {
            return coro_handle.promise().current_value;
        }

        const T* operator->() const {
            return &(operator*());
        }

        bool operator==(const iterator& other) const {
            return coro_handle == other.coro_handle;
        }

        bool operator!=(const iterator& other) const {
            return !(*this == other);
        }

    private:
        std::coroutine_handle<promise_type> coro_handle;

        void advance() {
            if (coro_handle && !coro_handle.done()) {
                coro_handle.resume();
                if (coro_handle.done()) {
                    coro_handle = nullptr;
                }
            } else {
                coro_handle = nullptr;
            }
        }
    };

    explicit generator(std::coroutine_handle<promise_type> h) : coro_handle(h) {}

    ~generator() {
        if (coro_handle) {
            coro_handle.destroy();
        }
    }

    // Move-only type
    generator(const generator&) = delete;
    generator& operator=(const generator&) = delete;
    
    generator(generator&& other) noexcept : coro_handle(other.coro_handle) {
        other.coro_handle = nullptr;
    }
    
    generator& operator=(generator&& other) noexcept {
        if (this != &other) {
            if (coro_handle) {
                coro_handle.destroy();
            }
            coro_handle = other.coro_handle;
            other.coro_handle = nullptr;
        }
        return *this;
    }

    iterator begin() {
        return iterator{coro_handle};
    }

    iterator end() {
        return iterator{};
    }

private:
    std::coroutine_handle<promise_type> coro_handle;
};