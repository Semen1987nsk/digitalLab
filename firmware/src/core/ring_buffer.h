#pragma once

#include <cstdint>
#include <cstring>

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
    
    // Флаги валидности
    uint16_t valid_flags;
    
    // Проверка валидности конкретного поля
    bool isValid(uint8_t field) const {
        return (valid_flags & (1 << field)) != 0;
    }
    
    void setValid(uint8_t field) {
        valid_flags |= (1 << field);
    }
};

// Индексы полей для valid_flags
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
};

/// Потокобезопасный кольцевой буфер
/// Используется для накопления данных при высокочастотном опросе
template<typename T, size_t SIZE>
class RingBuffer {
public:
    RingBuffer() : head_(0), tail_(0), count_(0) {
        memset(buffer_, 0, sizeof(buffer_));
    }
    
    /// Добавить элемент (перезаписывает старые при переполнении)
    bool push(const T& item) {
        buffer_[head_] = item;
        head_ = (head_ + 1) % SIZE;
        
        if (count_ < SIZE) {
            count_++;
        } else {
            // Буфер полон - сдвигаем tail
            tail_ = (tail_ + 1) % SIZE;
        }
        return true;
    }
    
    /// Извлечь элемент
    bool pop(T& item) {
        if (count_ == 0) {
            return false;
        }
        
        item = buffer_[tail_];
        tail_ = (tail_ + 1) % SIZE;
        count_--;
        return true;
    }
    
    /// Получить элемент без извлечения
    bool peek(T& item) const {
        if (count_ == 0) {
            return false;
        }
        item = buffer_[tail_];
        return true;
    }
    
    /// Получить последний добавленный элемент
    bool peekLast(T& item) const {
        if (count_ == 0) {
            return false;
        }
        size_t lastIdx = (head_ == 0) ? SIZE - 1 : head_ - 1;
        item = buffer_[lastIdx];
        return true;
    }
    
    /// Количество элементов
    size_t count() const { return count_; }
    
    /// Пустой ли буфер
    bool isEmpty() const { return count_ == 0; }
    
    /// Полный ли буфер
    bool isFull() const { return count_ == SIZE; }
    
    /// Очистить буфер
    void clear() {
        head_ = 0;
        tail_ = 0;
        count_ = 0;
    }
    
    /// Ёмкость буфера
    size_t capacity() const { return SIZE; }

private:
    T buffer_[SIZE];
    volatile size_t head_;
    volatile size_t tail_;
    volatile size_t count_;
};
