/**
  ******************************************************************************
  * @file    ${file_base}.hpp
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

#ifndef __GREMSY_PROFILES_PM1505_H__
#define __GREMSY_PROFILES_PM1505_H__

/* Includes ------------------------------------------------------------------*/

/* Exported types ------------------------------------------------------------*/

#if(GREMSY_MOTOR_TYPE == 0x01)

/// Cac define phu thuoc vao loai dong co

/// Thong tin bo test
#define MOTOR_NAME                  "PM1505"

/// Cac QC_Profile kiem tra dien tro
#define GREMSY_QC_PROFILES_RESISTANCE_NORMAL     9.0f
#define GREMSY_QC_PROFILES_RESISTANCE_THRESHOLD  0.5f
#define GREMSY_QC_PROFILES_RESISTANCE_PERCENT    10.0f

/// Cac QC_Profile kiem tra Nonlinear
#define GREMSY_QC_PROFILES_NONLINEAR_ANGLE_MAX  5.0f // 3505_GD_PAN123(3.5f, default : 1.7f)

/// Cac QC_Profile kiem tra Power Min Move (%)
#define GREMSY_QC_PROFILES_PWR_MIN_NORMAL_PERCENT 14.0f

/// So cap cuc dong co
#define MOTOR_NUM_POLSE             12 //<PIXY>

/// Goc kiem tra chieu dong co
#define MOTOR_CHECK_DIR_ANGLE       90.0f

/// So mau kiem tra dien tro dong co
#define MOTOR_RES_SAMPLE            1000

/// Thoi gian doi truoc khi doc gia tri dien tro (ms)
#define MOTOR_RES_TIME_SLEEP        500

/// Dien tro toi da hien thi, cao hon la N/A
#define MOTOR_RES_LOST_PHASE        50.0f

/// Hieu chinh he so PID dieu khien vi tri
#define MOTOR_MOVE_POS_KP           0.5f
#define MOTOR_MOVE_POS_KI           0.0005f
#define MOTOR_MOVE_POS_KD           2.0f
#define MOTOR_MOVE_POS_I_LIMIT      5

/// Pos toi da khi dieu khien dong co
#define MOTOR_MOVE_POS_MAX          100

/// Goc sai lech dieu khien vi tri
#define MOTOR_MOVE_POS_ERROR        0.1f

/// Goc kiem tra non-linear
#define MOTOR_NONLINEAR_ANGLE       370.0f

/// Thoi gian doi moi lan tang pos
#define MOTOR_NONLINEAR_SLEEP_TIME  5

/// So lan tinh trung binh khi kiem tra non-linear
#define MOTOR_NONLINEAR_SAMPLES     5

/// Pos cong them khi kiem tra non-linear
#define MOTOR_NONLINEAR_POS_INCREASE 256

/// Thoi gian sleep khi lock o goc 0 kiem tra power min
#define MOTOR_PWR_MIN_TIME_LOCK     50

/// Pos cong them khi kiem tra power min
#define MOTOR_PWR_MIN_POS_INCREASE  2048

/// Error tang power khi kiem tra power min
#define MOTOR_PWR_MIN_ANGLE_ERROR   0.1f

/// Goc quay khi kiem tra power min
#define MOTOR_PWR_MIN_ANGLE_ROTATION 1080.0f

/// Cong suat nguon toi da kiem tra, giam thoi gian kiem tra
#define MOTOR_PWR_MIN_MAXIMUM_CHECK 0.15f

/// Cong suat nguon cong them moi lan tang
#define MOTOR_PWR_MIN_POWER_INCREASE 0.001f;

/// Cong suat nguon bat dau test
#define MOTOR_PWR_MIN_POWER_START    0.075f

/// Config profiles encoder
#define MA600_BCT_ENA				0x01
#define MA600_BCT_TRIM				3

static const int16_t MA600_OFFSET_TABLE[32] = {0};

#endif /// GREMSY_MOTOR_TYPE

/* Exported constants --------------------------------------------------------*/

/* Exported macro ------------------------------------------------------------*/

/* Exported class ------------------------------------------------------------*/

/* Exported functions --------------------------------------------------------*/

#endif /* __GREMSY_PROFILES_PM3505_H__ */

/************************ (C) COPYRIGHT GREMSY *****END OF FILE****************/
