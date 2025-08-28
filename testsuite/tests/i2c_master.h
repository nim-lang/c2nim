/*
 * SPDX-FileCopyrightText: 2023-2024 Espressif Systems (Shanghai) CO LTD
 *
 * SPDX-License-Identifier: Apache-2.0
 */

#anonymousAsFields


#pragma once

#include <stdint.h>
#include "esp_err.h"
#include "driver/i2c_types.h"
#include "hal/gpio_types.h"

#ifdef __cplusplus
extern "C" {
#endif

/**
 * @brief I2C master bus specific configurations
 */
typedef struct {
    i2c_port_num_t i2c_port;              /*!< I2C port number, `-1` for auto selecting, (not include LP I2C instance) */
    gpio_num_t sda_io_num;                /*!< GPIO number of I2C SDA signal, pulled-up internally */
    gpio_num_t scl_io_num;                /*!< GPIO number of I2C SCL signal, pulled-up internally */
    union {
        i2c_clock_source_t clk_source;        /*!< Clock source of I2C master bus */
#if SOC_LP_I2C_SUPPORTED
        lp_i2c_clock_source_t lp_source_clk;       /*!< LP_UART source clock selection */
#endif
    };
    uint8_t glitch_ignore_cnt;            /*!< If the glitch period on the line is less than this value, it can be filtered out, typically value is 7 (unit: I2C module clock cycle)*/
    int intr_priority;                    /*!< I2C interrupt priority, if set to 0, driver will select the default priority (1,2,3). */
    size_t trans_queue_depth;             /*!< Depth of internal transfer queue, increase this value can support more transfers pending in the background, only valid in asynchronous transaction. (Typically max_device_num * per_transaction)*/
    struct {
        uint32_t enable_internal_pullup: 1;  /*!< Enable internal pullups. Note: This is not strong enough to pullup buses under high-speed frequency. Recommend proper external pull-up if possible */
        uint32_t allow_pd:               1;  /*!< If set, the driver will backup/restore the I2C registers before/after entering/exist sleep mode.
                                              By this approach, the system can power off I2C's power domain.
                                              This can save power, but at the expense of more RAM being consumed */
    } flags;                              /*!< I2C master config flags */
} i2c_master_bus_config_t;

#define I2C_DEVICE_ADDRESS_NOT_USED    (0xffff) /*!< Skip carry address bit in driver transmit and receive */


#ifdef __cplusplus
}
#endif
