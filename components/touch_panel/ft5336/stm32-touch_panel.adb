------------------------------------------------------------------------------
--                                                                          --
--                  Copyright (C) 2015-2016, AdaCore                        --
--                                                                          --
--  Redistribution and use in source and binary forms, with or without      --
--  modification, are permitted provided that the following conditions are  --
--  met:                                                                    --
--     1. Redistributions of source code must retain the above copyright    --
--        notice, this list of conditions and the following disclaimer.     --
--     2. Redistributions in binary form must reproduce the above copyright --
--        notice, this list of conditions and the following disclaimer in   --
--        the documentation and/or other materials provided with the        --
--        distribution.                                                     --
--     3. Neither the name of STMicroelectronics nor the names of its       --
--        contributors may be used to endorse or promote products derived   --
--        from this software without specific prior written permission.     --
--                                                                          --
--   THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS    --
--   "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT      --
--   LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR  --
--   A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT   --
--   HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, --
--   SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT       --
--   LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,  --
--   DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY  --
--   THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT    --
--   (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE  --
--   OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.   --
--                                                                          --
------------------------------------------------------------------------------

--  Based on ft5336.h from MCD Application Team

with Ada.Real_Time; use Ada.Real_Time;
with Ada.Unchecked_Conversion;

with STM32.Board;   use STM32.Board;
with STM32.Device;  use STM32.Device;
with STM32.I2C;     use STM32.I2C;
with STM32.LCD;

package body STM32.Touch_Panel is

   --  I2C Slave address of touchscreen FocalTech FT5336
   TP_ADDR  : constant := 16#70#;

   function TP_Read (Reg : Byte; Status : out I2C_Status) return Byte
     with Inline;
   --  Reads a Touch Panel register value

   procedure TP_Write (Reg : Byte; Data :  Byte; Status : out I2C_Status)
     with Inline;
   --  Write a Touch Panel register value

   function Check_Id return Boolean;
   --  Check the device Id: returns true on a FT5336 touch panel, False is
   --  none is found.

   procedure TP_Set_Use_Interrupts (Enabled : Boolean);
   --  Whether the touch panel uses interrupts of polling to process touch
   --  information

   function Get_Touch_State
     (Touch_Id : Byte;
      Status   : out I2C_Status) return TP_Touch_State;
   --  Retrieves the position and pressure information of the specified
   --  touch

   pragma Warnings (Off, "* is not referenced");

   ------------------------------------------------------------
   -- Definitions for FT5336 I2C register addresses on 8 bit --
   ------------------------------------------------------------

   --  Current mode register of the FT5336 (R/W)
   FT5336_DEV_MODE_REG                 : constant Byte := 16#00#;

   --  Possible values of FT5336_DEV_MODE_REG
   FT5336_DEV_MODE_WORKING             : constant Byte := 16#00#;
   FT5336_DEV_MODE_FACTORY             : constant Byte := 16#04#;

   FT5336_DEV_MODE_MASK                : constant Byte := 16#07#;
   FT5336_DEV_MODE_SHIFT               : constant Byte := 16#04#;

   --  Gesture ID register
   FT5336_GEST_ID_REG                  : constant Byte := 16#01#;

   --  Possible values of FT5336_GEST_ID_REG
   FT5336_GEST_ID_NO_GESTURE           : constant Byte := 16#00#;
   FT5336_GEST_ID_MOVE_UP              : constant Byte := 16#10#;
   FT5336_GEST_ID_MOVE_RIGHT           : constant Byte := 16#14#;
   FT5336_GEST_ID_MOVE_DOWN            : constant Byte := 16#18#;
   FT5336_GEST_ID_MOVE_LEFT            : constant Byte := 16#1C#;
   FT5336_GEST_ID_SINGLE_CLICK         : constant Byte := 16#20#;
   FT5336_GEST_ID_DOUBLE_CLICK         : constant Byte := 16#22#;
   FT5336_GEST_ID_ROTATE_CLOCKWISE     : constant Byte := 16#28#;
   FT5336_GEST_ID_ROTATE_C_CLOCKWISE   : constant Byte := 16#29#;
   FT5336_GEST_ID_ZOOM_IN              : constant Byte := 16#40#;
   FT5336_GEST_ID_ZOOM_OUT             : constant Byte := 16#49#;

   --  Touch Data Status register : gives number of active touch points (0..5)
   FT5336_TD_STAT_REG                  : constant Byte := 16#02#;

   --  Values related to FT5336_TD_STAT_REG
   FT5336_TD_STAT_MASK                 : constant Byte := 16#0F#;
   FT5336_TD_STAT_SHIFT                : constant Byte := 16#00#;

   --  Values Pn_XH and Pn_YH related
   FT5336_TOUCH_EVT_FLAG_PRESS_DOWN    : constant Byte := 16#00#;
   FT5336_TOUCH_EVT_FLAG_LIFT_UP       : constant Byte := 16#01#;
   FT5336_TOUCH_EVT_FLAG_CONTACT       : constant Byte := 16#02#;
   FT5336_TOUCH_EVT_FLAG_NO_EVENT      : constant Byte := 16#03#;

   FT5336_TOUCH_EVT_FLAG_SHIFT         : constant Byte := 16#06#;
   FT5336_TOUCH_EVT_FLAG_MASK          : constant Byte := 2#1100_0000#;

   FT5336_TOUCH_POS_MSB_MASK           : constant Byte := 16#0F#;
   FT5336_TOUCH_POS_MSB_SHIFT          : constant Byte := 16#00#;

   --  Values Pn_XL and Pn_YL related
   FT5336_TOUCH_POS_LSB_MASK           : constant Byte := 16#FF#;
   FT5336_TOUCH_POS_LSB_SHIFT          : constant Byte := 16#00#;


   --  Values Pn_WEIGHT related
   FT5336_TOUCH_WEIGHT_MASK            : constant Byte := 16#FF#;
   FT5336_TOUCH_WEIGHT_SHIFT           : constant Byte := 16#00#;


   --  Values related to FT5336_Pn_MISC_REG
   FT5336_TOUCH_AREA_MASK              : constant Byte := 2#0100_0000#;
   FT5336_TOUCH_AREA_SHIFT             : constant Byte := 16#04#;

   type FT5336_Pressure_Registers is record
      XH_Reg     : Byte;
      XL_Reg     : Byte;
      YH_Reg     : Byte;
      YL_Reg     : Byte;
      --  Touch Pressure register value (R)
      Weight_Reg : Byte;
      --  Touch area register
      Misc_Reg   : Byte;
   end record;

   FT5336_Px_Regs                : constant array (Byte range <>)
                                      of FT5336_Pressure_Registers  :=
                                     (1  => (XH_Reg     => 16#03#,
                                             XL_Reg     => 16#04#,
                                             YH_Reg     => 16#05#,
                                             YL_Reg     => 16#06#,
                                             Weight_Reg => 16#07#,
                                             Misc_Reg   => 16#08#),
                                      2  => (XH_Reg     => 16#09#,
                                             XL_Reg     => 16#0A#,
                                             YH_Reg     => 16#0B#,
                                             YL_Reg     => 16#0C#,
                                             Weight_Reg => 16#0D#,
                                             Misc_Reg   => 16#0E#),
                                      3  => (XH_Reg     => 16#0F#,
                                             XL_Reg     => 16#10#,
                                             YH_Reg     => 16#11#,
                                             YL_Reg     => 16#12#,
                                             Weight_Reg => 16#13#,
                                             Misc_Reg   => 16#14#),
                                      4  => (XH_Reg     => 16#15#,
                                             XL_Reg     => 16#16#,
                                             YH_Reg     => 16#17#,
                                             YL_Reg     => 16#18#,
                                             Weight_Reg => 16#19#,
                                             Misc_Reg   => 16#1A#),
                                      5  => (XH_Reg     => 16#1B#,
                                             XL_Reg     => 16#1C#,
                                             YH_Reg     => 16#1D#,
                                             YL_Reg     => 16#1E#,
                                             Weight_Reg => 16#1F#,
                                             Misc_Reg   => 16#20#),
                                      6  => (XH_Reg     => 16#21#,
                                             XL_Reg     => 16#22#,
                                             YH_Reg     => 16#23#,
                                             YL_Reg     => 16#24#,
                                             Weight_Reg => 16#25#,
                                             Misc_Reg   => 16#26#),
                                      7  => (XH_Reg     => 16#27#,
                                             XL_Reg     => 16#28#,
                                             YH_Reg     => 16#29#,
                                             YL_Reg     => 16#2A#,
                                             Weight_Reg => 16#2B#,
                                             Misc_Reg   => 16#2C#),
                                      8  => (XH_Reg     => 16#2D#,
                                             XL_Reg     => 16#2E#,
                                             YH_Reg     => 16#2F#,
                                             YL_Reg     => 16#30#,
                                             Weight_Reg => 16#31#,
                                             Misc_Reg   => 16#32#),
                                      9  => (XH_Reg     => 16#33#,
                                             XL_Reg     => 16#34#,
                                             YH_Reg     => 16#35#,
                                             YL_Reg     => 16#36#,
                                             Weight_Reg => 16#37#,
                                             Misc_Reg   => 16#38#),
                                      10 => (XH_Reg     => 16#39#,
                                             XL_Reg     => 16#3A#,
                                             YH_Reg     => 16#3B#,
                                             YL_Reg     => 16#3C#,
                                             Weight_Reg => 16#3D#,
                                             Misc_Reg   => 16#3E#));

   --  Threshold for touch detection
   FT5336_TH_GROUP_REG                 : constant Byte := 16#80#;

   --  Values FT5336_TH_GROUP_REG : threshold related
   FT5336_THRESHOLD_MASK               : constant Byte := 16#FF#;
   FT5336_THRESHOLD_SHIFT              : constant Byte := 16#00#;

   --  Filter function coefficients
   FT5336_TH_DIFF_REG                  : constant Byte := 16#85#;

   --  Control register
   FT5336_CTRL_REG                     : constant Byte := 16#86#;

   --  Values related to FT5336_CTRL_REG

   --  Will keep the Active mode when there is no touching
   FT5336_CTRL_KEEP_ACTIVE_MODE        : constant Byte := 16#00#;

   --  Switching from Active mode to Monitor mode automatically when there
   --  is no touching
   FT5336_CTRL_KEEP_AUTO_SWITCH_MONITOR_MODE : constant Byte := 16#01#;

   --  The time period of switching from Active mode to Monitor mode when
   --  there is no touching
   FT5336_TIMEENTERMONITOR_REG               : constant Byte := 16#87#;

   --  Report rate in Active mode
   FT5336_PERIODACTIVE_REG             : constant Byte := 16#88#;

   --  Report rate in Monitor mode
   FT5336_PERIODMONITOR_REG            : constant Byte := 16#89#;

   --  The value of the minimum allowed angle while Rotating gesture mode
   FT5336_RADIAN_VALUE_REG             : constant Byte := 16#91#;

   --  Maximum offset while Moving Left and Moving Right gesture
   FT5336_OFFSET_LEFT_RIGHT_REG        : constant Byte := 16#92#;

   --  Maximum offset while Moving Up and Moving Down gesture
   FT5336_OFFSET_UP_DOWN_REG           : constant Byte := 16#93#;

   --  Minimum distance while Moving Left and Moving Right gesture
   FT5336_DISTANCE_LEFT_RIGHT_REG      : constant Byte := 16#94#;

   --  Minimum distance while Moving Up and Moving Down gesture
   FT5336_DISTANCE_UP_DOWN_REG         : constant Byte := 16#95#;

   --  Maximum distance while Zoom In and Zoom Out gesture
   FT5336_DISTANCE_ZOOM_REG            : constant Byte := 16#96#;

   --  High 8-bit of LIB Version info
   FT5336_LIB_VER_H_REG                : constant Byte := 16#A1#;

   --  Low 8-bit of LIB Version info
   FT5336_LIB_VER_L_REG                : constant Byte := 16#A2#;

   --  Chip Selecting
   FT5336_CIPHER_REG                   : constant Byte := 16#A3#;

   --  Interrupt mode register (used when in interrupt mode)
   FT5336_GMODE_REG                    : constant Byte := 16#A4#;

   FT5336_G_MODE_INTERRUPT_MASK        : constant Byte := 16#03#;

   --  Possible values of FT5336_GMODE_REG
   FT5336_G_MODE_INTERRUPT_POLLING     : constant Byte := 16#00#;
   FT5336_G_MODE_INTERRUPT_TRIGGER     : constant Byte := 16#01#;

   --  Current power mode the FT5336 system is in (R)
   FT5336_PWR_MODE_REG                 : constant Byte := 16#A5#;

   --  FT5336 firmware version
   FT5336_FIRMID_REG                   : constant Byte := 16#A6#;

   --  FT5336 Chip identification register
   FT5336_CHIP_ID_REG                  : constant Byte := 16#A8#;

   --   Possible values of FT5336_CHIP_ID_REG
   FT5336_ID_VALUE                     : constant Byte := 16#51#;

   --  Release code version
   FT5336_RELEASE_CODE_ID_REG          : constant Byte := 16#AF#;

   --  Current operating mode the FT5336 system is in (R)
   FT5336_STATE_REG                    : constant Byte := 16#BC#;

   pragma Warnings (On, "* is not referenced");

   -------------
   -- TS_Read --
   -------------

   function TP_Read (Reg : Byte; Status : out I2C_Status) return Byte
   is
      Ret : I2C_Data (1 .. 1);
   begin
      STM32.I2C.Mem_Read
        (TP_I2C,
         TP_ADDR,
         Short (Reg),
         Memory_Size_8b,
         Ret,
         Status,
         1000);
      return Ret (1);
   end TP_Read;

   -------------
   -- TS_Read --
   -------------

   procedure TP_Write (Reg : Byte; Data :  Byte; Status : out I2C_Status)
   is
   begin
      STM32.I2C.Mem_Write
        (TP_I2C,
         TP_ADDR,
         Short (Reg),
         Memory_Size_8b,
         (1 => Data),
         Status,
         1000);
   end TP_Write;

   ---------------------------
   -- TP_Set_Use_Interrupts --
   ---------------------------

   procedure TP_Set_Use_Interrupts (Enabled : Boolean)
   is
      Reg_Value : Byte := 0;
      Status    : I2C_Status with Unreferenced;
   begin
      if Enabled then
         Reg_Value := FT5336_G_MODE_INTERRUPT_TRIGGER;
      else
         Reg_Value := FT5336_G_MODE_INTERRUPT_POLLING;
      end if;

      TP_Write (FT5336_GMODE_REG, Reg_Value, Status);
   end TP_Set_Use_Interrupts;

   -------------
   -- Read_Id --
   -------------

   function Check_Id return Boolean
   is
      Id     : Byte;
      Status : I2C_Status;
   begin
      for J in 1 .. 3 loop
         Id := TP_Read (FT5336_CHIP_ID_REG, Status);

         if Id = FT5336_ID_VALUE then
            return True;
         end if;

         if Status = Err_Error then
            return False;
         end if;
      end loop;

      return False;
   end Check_Id;

   ----------------
   -- Initialize --
   ----------------

   function Initialize return Boolean is
   begin
      Initialize_I2C_GPIO (TP_I2C);

      --  Wait at least 200ms after power up before accessing the TP registers
      delay until Clock + Milliseconds (200);

      Configure_I2C (TP_I2C);

      TP_Set_Use_Interrupts (False);

      return Check_Id;
   end Initialize;

   ----------------
   -- Initialize --
   ----------------

   procedure Initialize is
      Ret : Boolean with Unreferenced;
   begin
      Ret := Initialize;
   end Initialize;

   ------------------
   -- Detect_Touch --
   ------------------

   function Detect_Touch return Natural
   is
     Status   : I2C_Status;
     Nb_Touch : Byte := 0;
   begin
      Nb_Touch := TP_Read (FT5336_TD_STAT_REG, Status);

      if Status /= Ok then
         return 0;
      end if;

      Nb_Touch := Nb_Touch and FT5336_TD_STAT_MASK;

      if Nb_Touch > FT5336_Px_Regs'Last then
         --  Overflow: set to 0
         Nb_Touch := 0;
      end if;

      return Natural (Nb_Touch);
   end Detect_Touch;

   ---------------------
   -- Get_Touch_State --
   ---------------------

   function Get_Touch_State
     (Touch_Id : Byte;
      Status   : out I2C_Status) return TP_Touch_State
   is
      type Short_HL_Type is record
         High, Low : Byte;
      end record with Size => 16;
      for Short_HL_Type use record
         High at 1 range 0 .. 7;
         Low  at 0 range 0 .. 7;
      end record;

      function To_Short is
        new Ada.Unchecked_Conversion (Short_HL_Type, Short);

      RX   : Natural;
      RY   : Natural;
      Rtmp : Natural;
      Ret  : TP_Touch_State;
      Regs : FT5336_Pressure_Registers;
      Tmp  : Short_HL_Type;

   begin
      if Touch_Id > 10 then
         Status := Err_Error;
         return (others => 0);
      end if;

      --  X/Y are swaped from the screen coordinates

      Regs := FT5336_Px_Regs (Touch_Id);

      Tmp.Low := TP_Read (Regs.XL_Reg, Status);

      if Status /= Ok then
         return Ret;
      end if;

      Tmp.High := TP_Read (Regs.XH_Reg, Status) and FT5336_TOUCH_POS_MSB_MASK;

      if Status /= Ok then
         return Ret;
      end if;

      RY := Natural (To_Short (Tmp) - 1);

      Tmp.Low := TP_Read (Regs.YL_Reg, Status);

      if Status /= Ok then
         return Ret;
      end if;

      Tmp.High := TP_Read (Regs.YH_Reg, Status) and FT5336_TOUCH_POS_MSB_MASK;

      if Status /= Ok then
         return Ret;
      end if;

      RX := Natural (To_Short (Tmp) - 1);

      Ret.Weight := Natural (TP_Read (Regs.Weight_Reg, Status));

      if Status /= Ok then
         Ret.Weight := 0;
         return Ret;
      end if;

      if LCD.SwapXY then
         RTmp := RX;
         RX   := RY;
         RY   := RTmp;
         RX   := STM32.LCD.Pixel_Width - RX - 1;
      end if;

      RX := Natural'Max (0, RX);
      RY := Natural'Max (0, RY);
      RX := Natural'Min (LCD.Pixel_Width - 1, RX);
      RY := Natural'Min (LCD.Pixel_Height - 1, RY);

      Ret.X := RX;
      Ret.Y := RY;

      return Ret;
   end Get_Touch_State;

   ---------------
   -- Get_State --
   ---------------

   function Get_State return TP_State
   is
      Status  : I2C_Status;
      N_Touch : constant Natural := Detect_Touch;
      State   : TP_State (1 .. N_Touch);

   begin
      if N_Touch = 0 then
         return (1 .. 0 => <>);
      end if;

      for J in State'Range loop
         State (J) := Get_Touch_State (Byte (J), Status);
         if Status /= Ok then
            return (1 .. 0 => <>);
         end if;
      end loop;

      return State;
   end Get_State;

end STM32.Touch_Panel;