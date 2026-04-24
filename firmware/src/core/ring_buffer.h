#pragma once

#include <cstdint>
#include <cstring>
#include <freertos/FreeRTOS.h>
#include <freertos/semphr.h>

// =============================================================================
// Кольцевой буфер для хранения измерений (размещается в PSRAM)
// =============================================================================

/// Структура пакета данных (соответствует Protobuf схеме)
struct SensorPacket {
    uint32_t timestamp_ms;
    
    // Расстояние
    float distance_mm;
    
    // Электричество
    float voltage_v;
    float current_a;
    float power_w;
    
    // Окружающая среда
    float temperature_c;
    float pressure_pa;
    float humidity_pct;
    
    // Движение
    float accel_x;
    float accel_y;
    float accel_z;
    float gyro_x;
    float gyro_y;
    float gyro_z;
    
    // Термопара
    float thermocouple_c;

    // Расширенные поля (для BLE 80-byte packet)
    float magnetic_field_mt;
    float force_n;
    float lux_lx;
    float radiation_cpm;
    
    // Флаги валидности (uint32_t — 18 полей, нужно >16 бит)
    uint32_t valid_flags;
    
    // Проверка валидности конкретного поля
    bool isValid(uint8_t field) const {
        return (valid_flags & (1 << field)) != 0;
    }
    
    void setValid(uint8_t field) {
        valid_flags |= (1 << field);
    }
};

// Индексы полей для valid_flags
// ВАЖНО: Должны совпадать с _ValidField в ble_hal.dart!
enum SensorField : uint8_t {
    FIELD_DISTANCE = 0,
    FIELD_VOLTAGE = 1,
    FIELD_CURRENT = 2,
    FIELD_POWER = 3,
    FIELD_TEMPERATURE = 4,
    FIELD_PRESSURE = 5,
    FIELD_HUMIDITY = 6,
    FIELD_ACCEL_X = 7,
    FIELD_ACCEL_Y = 8,
    FIELD_ACCEL_Z = 9,
    FIELD_GYRO_X = 10,
    FIELD_GYRO_Y = 11,
    FIELD_GYRO_Z = 12,
    FIELD_THERMOCOUPLE = 13,
    FIELD_MAGNETIC = 14,
    FIELD_FORCE = 15,
    FIELD_LUX = 16,
    FIELD_RADIATION = 17,
};

/// Потокобезопасный кольцевой буфер (размещается в PSRAM через heap)
/// Используется для накопления данных при высокочастотном опросе
/// Защищён FreeRTOS мьютексом для безопасного доступа из разных задач/ядер
template<typename T, size_t SIZE>
class RingBuffer {
public:
    RingBuffer() : head_(0), tail_(0), count_(0), buffer_(nullptr) {
        // Выделяем память в PSRAM (heap), а не на стеке.
        // SIZE=10000 x sizeof(SensorPacket)≈72B = 720KB — не влезет в стек!
#ifdef BOARD_HAS_PSRAM
        buffer_ = static_cast<T*>(ps_calloc(SIZE, sizeof(T)));
#else
        buffer_ = static_cast<T*>(calloc(SIZE, sizeof(T)));
#endif
        configASSERT(buffer_ != nullptr);  // Буфер обязателен
        
        mutex_ = xSemaphoreCreateMutex();
        configASSERT(mutex_ != nullptr);
    }
    
    ~RingBuffer() {
        if (mutex_ != nullptr) {
            vSemaphoreDelete(mutex_);
        }
        free(buffer_);
        buffer_ = nullptr;
    }
    
    // Запрет копирования (мьютекс нельзя копировать)
    RingBuffer(const RingBuffer&) = delete;
    RingBuffer& operator=(const RingBuffer&) = delete;
    
    /// Добавить элемент (перезаписывает старые при переполнении)
    /// Вызывается из Core 1 (задача датчиков)
    bool push(const T& item) {
        if (xSemaphoreTake(mutex_, pdMS_TO_TICKS(10)) != pdTRUE) {
            return false;  // Не удалось захватить мьютекс
        }
        
        buffer_[head_] = item;
        head_ = (head_ + 1) % SIZE;
        
        if (count_ < SIZE) {
            count_++;
        } else {
            // Буфер полон - сдвигаем tail
            tail_ = (tail_ + 1) % SIZE;
        }
        
        xSemaphoreGive(mutex_);
        return true;
    }
    
    /// Извлечь элемент
    /// Вызывается из Core 0 (BLE/Web для отправки данных)
    bool pop(T& item) {
        if (xSemaphoreTake(mutex_, pdMS_TO_TICKS(10)) != pdTRUE) {
            return false;
        }
        
        if (count_ == 0) {
            xSemaphoreGive(mutex_);
            return false;
        }
        
        item = buffer_[tail_];
        tail_ = (tail_ + 1) % SIZE;
        count_--;
        
        xSemaphoreGive(mutex_);
        return true;
    }
    
    /// Получить элемент без извлечения
    bool peek(T& item) const {
        if (xSemaphoreTake(mutex_, pdMS_TO_TICKS(10)) != pdTRUE) {
            return false;
        }
        
        if (count_ == 0) {
            xSemaphoreGive(mutex_);
            return false;
        }
        
        item = buffer_[tail_];
        xSemaphoreGive(mutex_);
        return true;
    }
    
    /// Получить последний добавленный элемент
    bool peekLast(T& item) const {
        if (xSemaphoreTake(mutex_, pdMS_TO_TICKS(10)) != pdTRUE) {
            return false;
        }
        
        if (count_ == 0) {
            xSemaphoreGive(mutex_);
            return false;
        }
        
        size_t lastIdx = (head_ == 0) ? SIZE - 1 : head_ - 1;
        item = buffer_[lastIdx];
        xSemaphoreGive(mutex_);
        return true;
    }

    /// Получить элемент по индексу (0 = oldest, count-1 = newest).
    /// Используется для CSV-экспорта через Web UI.
    bool peekAt(size_t index, T& item) const {
        if (xSemaphoreTake(mutex_, pdMS_TO_TICKS(10)) != pdTRUE) {
            return false;
        }
        if (index >= count_) {
            xSemaphoreGive(mutex_);
            return false;
        }
        size_t actualIdx = (tail_ + index) % SIZE;
        item = buffer_[actualIdx];
        xSemaphoreGive(mutex_);
        return true;
    }
    
    /// Количество элементов (потокобезопасно)
    size_t count() const {
        if (xSemaphoreTake(mutex_, pdMS_TO_TICKS(5)) != pdTRUE) {
            // Мьютекс занят — вернуть 0 вместо чтения без синхронизации.
            // На двухъядерном ESP32 чтение volatile size_t без мьютекса —
            // data race (Core 1 может быть посреди push/count_++ на другом ядре).
            return 0;
        }

        const size_t value = count_;
        xSemaphoreGive(mutex_);
        return value;
    }
    
    /// Пустой ли буфер
    bool isEmpty() const { return count() == 0; }
    
    /// Полный ли буфер
    bool isFull() const { return count() == SIZE; }
    
    /// Очистить буфер
    void clear() {
        if (xSemaphoreTake(mutex_, pdMS_TO_TICKS(50)) == pdTRUE) {
            head_ = 0;
            tail_ = 0;
            count_ = 0;
            xSemaphoreGive(mutex_);
        }
    }
    
    /// Ёмкость буфера
    size_t capacity() const { return SIZE; }

private:
    T* buffer_;  // Выделяется в PSRAM через ps_calloc()
    volatile size_t head_;
    volatile size_t tail_;
    volatile size_t count_;
    mutable SemaphoreHandle_t mutex_;
};
