##
##  SPDX-FileCopyrightText: 2023-2024 Espressif Systems (Shanghai) CO LTD
##
##  SPDX-License-Identifier: Apache-2.0
##

import
  esp_err, driver/i2c_types, hal/gpio_types

##
##  @brief I2C master bus specific configurations
##

type
  INNER_C_STRUCT_i2c_master_3* {.bycopy.} = object
    enable_internal_pullup* {.bitsize: 1.}: uint32_t
    ## !< Enable internal pullups. Note: This is not strong enough to pullup buses under high-speed frequency. Recommend proper external pull-up if possible
    allow_pd* {.bitsize: 1.}: uint32_t
    ## !< If set, the driver will backup/restore the I2C registers before/after entering/exist sleep mode.
    ##                                               By this approach, the system can power off I2C's power domain.
    ##                                               This can save power, but at the expense of more RAM being consumed

  i2c_master_bus_config_t* {.bycopy.} = object
    i2c_port*: i2c_port_num_t
    ## !< I2C port number, `-1` for auto selecting, (not include LP I2C instance)
    sda_io_num*: gpio_num_t
    ## !< GPIO number of I2C SDA signal, pulled-up internally
    scl_io_num*: gpio_num_t
    ## !< GPIO number of I2C SCL signal, pulled-up internally
    anon2_clk_source*: i2c_clock_source_t
    ## !< Clock source of I2C master bus
    when SOC_LP_I2C_SUPPORTED:
      var lp_source_clk*: lp_i2c_clock_source_t
      ## !< LP_UART source clock selection
    glitch_ignore_cnt*: uint8_t
    ## !< If the glitch period on the line is less than this value, it can be filtered out, typically value is 7 (unit: I2C module clock cycle)
    intr_priority*: cint
    ## !< I2C interrupt priority, if set to 0, driver will select the default priority (1,2,3).
    trans_queue_depth*: csize_t
    ## !< Depth of internal transfer queue, increase this value can support more transfers pending in the background, only valid in asynchronous transaction. (Typically max_device_num * per_transaction)
    flags*: INNER_C_STRUCT_i2c_master_3
    ## !< I2C master config flags


const
  I2C_DEVICE_ADDRESS_NOT_USED* = (0xffff) ## !< Skip carry address bit in driver transmit and receive
