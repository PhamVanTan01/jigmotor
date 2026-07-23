/**
  ******************************************************************************
  * @file    gremsyMotor.h
  * @author  Gremsy Team
  * @version V2.0.0
  * @date    ${date}
  * @brief   This file contains all the functions prototypes for the ${file_base}.cpp
  *          firmware library.
  *
  ******************************************************************************
  * @Copyright
  * COPYRIGHT NOTICE: (c) 2018 Gremsy. All rights reserved.
  *
  * The information contained herein is confidential
  * property of Company. The use, copying, transfer or
  * disclosure of such information is prohibited except
  * by express written agreement with Company.
  *
  ******************************************************************************
*/

/* Define to prevent recursive inclusion -------------------------------------*/

#ifndef __GREMSY_MOTOR_H__
#define __GREMSY_MOTOR_H__

/* Includes ------------------------------------------------------------------*/

/* Exported types ------------------------------------------------------------*/

/* Exported constants --------------------------------------------------------*/

/* Exported macro ------------------------------------------------------------*/

/* Exported class ------------------------------------------------------------*/

/* Exported functions --------------------------------------------------------*/
void gremsyMotorEnable(void);
void gremsyMotorDisable(void);
void gremsyMotorInit(void);
void gremsyMotorSetPWM(uint16_t pwm1, uint16_t pwm2, uint16_t pwm3);
void gremsyMotorSetOffset(uint16_t motorOffset);
void gremsyMotorMovePos(uint16_t pos, float power);
float gremsyMotorMoveAngle(float angle);
void gremsyMotorMoveSpeed(int16_t speed, float power);
void gremsyMotorPidSpeed(int16_t speed);
void gremsyMotorProcess(void);

#endif /* __GREMSY_MOTOR_H__ */

/************************ (C) COPYRIGHT GREMSY *****END OF FILE****************/
