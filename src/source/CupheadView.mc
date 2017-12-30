using Toybox.WatchUi as Ui;
using Toybox.Graphics as Gfx;
using Toybox.System as Sys;
using Toybox.Lang as Lang;
using Toybox.Application as App;
using Toybox.ActivityMonitor as Mon;
using Toybox.Timer as Tmr;

module Global {

	// Properties
	var propActivityType = 0;									// Activity type:
																// 0 - Steps,
																// 1 - Floors,
																// 2 - HR,
																// 3 - Calories,
																// 4 - Distance,
																// 5 - MoveBar
																// 6 - Steps %
																// 7 - Steps Left
																// 100 - Battery

	var propDateFormat = 0;										// Date format: 0 - None, 1 - DD.MM
	var propColorBackground = Gfx.COLOR_YELLOW;					// Background color
	var propColorForeground = Gfx.COLOR_BLACK;					// Time and Indicators color

	// Return value of [name] or Custom[name] property otherwise [def]
	function getPropertyColor(name, def) {
		var result = null;
		var value = App.getApp().getProperty(name);

		if (value == -1) {
			value = App.getApp().getProperty("Custom" + name);
			if (value != null) {
				result = value.toNumberWithBase(16);
			}
		} else {
			result = value;
		}

		return (result == null) ? def : result;
	}

	// Read updated settings
	function handlSettingUpdate() {
		propActivityType = App.getApp().getProperty("ActivityType");
		propDateFormat = App.getApp().getProperty("DateFormat");
		propColorBackground = getPropertyColor("BackgroundColor", Gfx.COLOR_YELLOW);
		propColorForeground = getPropertyColor("ForegroundColor", Gfx.COLOR_BLACK);
	}
}

class CupheadView extends Ui.WatchFace {

	// Constans
	hidden const SYMBOL_CONNECTED		= "a";							// Phone connected symbol
	hidden const SYMBOL_ALARM			= "c";							// Alarm symbol
	hidden const SYMBOL_NOTIFICATION		= "d";							// Notification symbol
	hidden const SYMBOL_DND				= "f";							// DoNotDisturb symbol
	hidden const SYMBOL_PM				= "p";							// PM symbol
	hidden const SYMBOL_CALENDAR			= "q.";							// Calendar symbol
	hidden const FONT_TIME				= Gfx.FONT_NUMBER_HOT;			// Time font
	hidden const MOVEBAR_VALUES			= ["move|", "Move|", "MOve|", "MOVe|", "MOVE|", "MOVE!"];

	// Variables
	hidden var screenShape = Sys.SCREEN_SHAPE_ROUND;						// Screen shape (see System.SCREEN_SHAPE_...)
	hidden var fntIcon;													// Symbols font
	hidden var fntIconH;													// Height of fntIcon
	hidden var fntIconHdiv2;												// Height/2 of fntIcon
	hidden var timeX3;													// Time X-coord when hour < 10 (h:mm)
	hidden var timeX4;													// Time X-coord when hour > 9 (hh:mm)
	hidden var timeY;													// Time y-coord
	hidden var timePmY;													// PM symbol y-coord
	hidden var arrAnimRezId;												// Array with animation frames rez id
	hidden var idxAnim;													// Animation frame index
	hidden var tmrAnim = null;											// Animation timer
	hidden var strTime = "";												// Current time to string
	hidden var isFullRedraw = true;


	function initialize() {
		WatchFace.initialize();

		tmrAnim = new Tmr.Timer();

		// <NOTE/> if array size changed from 6 change method timerCallback()
		arrAnimRezId = [Rez.Drawables.Cuphead_0,
						Rez.Drawables.Cuphead_2,
						Rez.Drawables.Cuphead_3,
						Rez.Drawables.Cuphead_4,
						Rez.Drawables.Cuphead_3,
						Rez.Drawables.Cuphead_1
					   ];

		// Get screen shape (since 1.2.0)
		screenShape = Sys.getDeviceSettings().screenShape;
	}

	// Load your resources here
	function onLayout(dc) {
		// Font params
		fntIcon = WatchUi.loadResource(Rez.Fonts.id_font_cuphead);
		//fntIcon = Gfx.FONT_SYSTEM_XTINY;
		fntIconH = Gfx.getFontHeight(fntIcon);
		fntIconHdiv2 = fntIconH/2 + 1;

		// Time y-coord
		var timeH = Gfx.getFontHeight(FONT_TIME);
		var y = (screenShape == Sys.SCREEN_SHAPE_SEMI_ROUND) ? 4 : 4 + fntIconH;
		timeY = (dc.getHeight() + y - 134 - timeH) / 2;
		// Time x-coord
		timeX3 = (dc.getWidth() - dc.getTextWidthInPixels("3:45",  FONT_TIME)) / 2;
		timeX4 = (dc.getWidth() - dc.getTextWidthInPixels("23:45", FONT_TIME)) / 2;

		// PM y-offset
		timePmY = timeY + (timeH - fntIconH)/2;

		// Text Time correct y-offset
		// For font System.FONT_SYSTEM_NUMBER_HOT
		// couze CIQ 1.x.x have ugly font descent (10, but realy 12) and ascent (real_font_height+unknown)
		// CIQ 2.x.x have correct font descent (= 0) and ascent (= font_height)
		timeY += (System.getDeviceSettings().monkeyVersion[0] < 2) ? -3 : 0;

		return true;
	}

	// Called when this View is brought to the foreground. Restore
	// the state of this View and prepare it to be shown. This includes
	// loading resources into memory.
	function onShow() {
		idxAnim = 0;
		Global.handlSettingUpdate();
		return true;
	}

	// Update the view
	function onUpdate(dc) {
		var width = dc.getWidth();
		var height = dc.getHeight();
		var widthDiv2 = width/2;

		// Load Character image
		// bitmap loaded during drawing and it's dimension hardcoded
		// bmp_dimension: frame_0 = 111x106, frame_1-4 = 111x93
		// where 58 = bmp_width/2 + bmp_shift_to_left = 111/2 + 3 = 55 + 5
		var bmpX = widthDiv2 - 58;
		var bmpY = height - 134;

		if (isFullRedraw) {
			// Full redraw

			// Get the current time and format it correctly
			var timeFormat = "$1$:$2$";

			var clockTime;
			if (Global.propDateFormat == 0) {
				clockTime = Sys.getClockTime();
			} else {
				clockTime = Toybox.Time.Gregorian.info(Toybox.Time.now(), (Global.propDateFormat == 3) ? Time.FORMAT_MEDIUM : Time.FORMAT_SHORT);
			}

			var hours = clockTime.hour;
			var isPM = false;
			if (!Sys.getDeviceSettings().is24Hour) {
				if (hours > 12) {
					hours = hours - 12;
					isPM = true;
				}
			}

			// Time x-coord for position indicators PM and Alarm (if semiround scrren shape)
			var tmX = (hours > 9) ? timeX4 : timeX3;

			strTime = Lang.format(timeFormat, [hours, clockTime.min.format("%02d")]);

			dc.setColor(Global.propColorForeground, Global.propColorBackground);
			dc.clear();

			// Draw Time
			dc.drawText(widthDiv2, timeY, FONT_TIME, strTime, Gfx.TEXT_JUSTIFY_CENTER);

			// Draw Indicators:

			// i0) Draw Time-PM indicator
			if (isPM) {
				dc.drawText(width - tmX + 4, timePmY, fntIcon, SYMBOL_PM, Gfx.TEXT_JUSTIFY_LEFT);
			}

			var settings = System.getDeviceSettings();
			// ------------------------------------------------------------------------------------------------------------------------
			// i1) Draw Alarm indicator
			if (settings.alarmCount > 0) {
				if (screenShape == Sys.SCREEN_SHAPE_SEMI_ROUND) {
					// Constant x-coord
					dc.drawText(34, timePmY, fntIcon, SYMBOL_ALARM, Gfx.TEXT_JUSTIFY_LEFT);
				} else {
					// Above Time
					dc.drawText(widthDiv2-8, 4, fntIcon, SYMBOL_ALARM, Gfx.TEXT_JUSTIFY_LEFT);
				}
			}
			// ------------------------------------------------------------------------------------------------------------------------
			// Y-coord for left/right indicators
			var lrsY = height/2 - fntIconHdiv2;

			// i2) DoNotDisturb/Notification indicator /+ notification count
			if ((settings has :doNotDisturb) and (settings.doNotDisturb)) {
				// i2.1) Draw DoNotDisturb indicator (since 2.1.0)
				if (settings.notificationCount > 0) {
					dc.drawText(width - 7, lrsY, fntIcon, settings.notificationCount.toString() + SYMBOL_DND, Gfx.TEXT_JUSTIFY_RIGHT);
				} else {
					dc.drawText(width - 23, lrsY, fntIcon, SYMBOL_DND, Gfx.TEXT_JUSTIFY_LEFT);
				}
			} else if (settings.notificationCount > 0) {
				// i2.2) Draw Notification indicator (since 1.2.0)
				dc.drawText(width - 8, lrsY, fntIcon, settings.notificationCount.toString() + SYMBOL_NOTIFICATION, Gfx.TEXT_JUSTIFY_RIGHT);
			}
			// ------------------------------------------------------------------------------------------------------------------------
			// i3) Draw PhoneConnected indicator (since 1.1.0)
			if (settings.phoneConnected) {
				if (Global.propDateFormat == 0) {
					// if date not shown
					dc.drawText(7, lrsY, fntIcon, SYMBOL_CONNECTED, Gfx.TEXT_JUSTIFY_LEFT);
				} else {
					// if date shown
					if (screenShape == Sys.SCREEN_SHAPE_SEMI_ROUND) {
						dc.drawText(17, height/4, fntIcon, SYMBOL_CONNECTED, Gfx.TEXT_JUSTIFY_LEFT);
					} else {
						dc.drawText(tmX - 18, timePmY, fntIcon, SYMBOL_CONNECTED, Gfx.TEXT_JUSTIFY_LEFT);
					}
				}
			}
			// ------------------------------------------------------------------------------------------------------------------------
			// Draw Date indicator
			if (Global.propDateFormat != 0) {
				// Draw calendar symbol and month - "s.m"
				dc.drawText(5, lrsY, fntIcon, /*"q."/**/SYMBOL_CALENDAR/**/ + clockTime.month, Gfx.TEXT_JUSTIFY_LEFT);
				// Draw day inside calendar symbol - "d"
				dc.setColor(Global.propColorBackground, Gfx.COLOR_TRANSPARENT);
				dc.drawText(5 + 10, lrsY, fntIcon, clockTime.day, Gfx.TEXT_JUSTIFY_CENTER);
				dc.setColor(Global.propColorForeground, Global.propColorBackground);
			}
			// ------------------------------------------------------------------------------------------------------------------------
			// Draw Activity Type:
			var activityValue = null;
			var activitySymbol = "";
			switch (Global.propActivityType) {
				// a0) Draw Steps (since 1.0.0)
				case 0: {
					activitySymbol = "g";
					var info = Mon.getInfo();
					if (info.steps != null) {
						activityValue = info.steps.toString();
					}
				} break;
				// a6) Draw Steps in Percentage (since 1.0.0)
				case 6: {
					activitySymbol = "g";
					var info = Mon.getInfo();
					if ((info.steps != null) and (info.stepGoal != null)) {
						activityValue = (100 * info.steps / info.stepGoal).toNumber().toString() + "%";
					}
				} break;
				// a7) Draw Steps Left (since 1.0.0)
				case 7: {
					activitySymbol = "g";
					var info = Mon.getInfo();
					if ((info.steps != null) and (info.stepGoal != null)) {
						var value = info.stepGoal - info.steps;
						if (value == 0) {
							activityValue = "0";
						} else if (value < 0) {
							activityValue = (-1 * value).toNumber().toString() + "+";
						} else {
							activityValue = value.toNumber().toString() + "-";
						}
					}
				} break;
				// a1) Draw Floors Climbed (since 2.1.0)
				case 1: {
					activitySymbol = "h";
					var info = Mon.getInfo();
					if ((info has :floorsClimbed) and (info.floorsClimbed != null)) {
						activityValue = info.floorsClimbed.toString();
					}
				} break;
				// a2) Draw HR (since 1.2.2)
				case 2: {
					activitySymbol = "i";
					if (Mon has :getHeartRateHistory) {
						var hrIterator = Mon.getHeartRateHistory(1, false);
						var sample = hrIterator.next();
						if (sample != null) {
							if (sample.heartRate != Mon.INVALID_HR_SAMPLE) {
								activityValue = sample.heartRate.toString();
							}
						}
					}
				} break;
				// a3) Draw Calories (since 1.0.0)
				case 3: {
					activitySymbol = "j";
					var info = Mon.getInfo();
					if (info.calories != null) {
						activityValue = info.calories.toString();
					}
				} break;
				// a4) Draw Distance (since 1.0.0)
				case 4: {
					activitySymbol = "k";
					var info = Mon.getInfo();
					if (info.distance != null) {
						// Miles in 1cm = 6.2137e-6, Kilometers in 1cm = 1e-5
						var value = (Sys.getDeviceSettings().distanceUnits == Sys.UNIT_METRIC) ? (info.distance * 1e-5) : (info.distance * 6.2137e-6);
						activityValue = value.format("%.1f");
					}
				} break;
				// a5) Draw MoveBarLevel (since 1.0.0)
				case 5: {
					activitySymbol = "";
					var info = Mon.getInfo();
					if (info.moveBarLevel != null) {
						activityValue = MOVEBAR_VALUES[info.moveBarLevel];
					}
				} break;
				// d8) Draw Battery remaining level in percentage (since 1.0.0)
				case 100: {
					activitySymbol = "l";
					activityValue = (System.getSystemStats().battery + 0.5).toNumber().toString() + "%";
				} break;
			}

			activityValue = (activityValue == null) ? "--" : activityValue;

			dc.drawText(widthDiv2, height-fntIconH-8, fntIcon, activitySymbol + activityValue,  Gfx.TEXT_JUSTIFY_CENTER);
		}
		else {
			// Redraw image and/ Time
			dc.setColor(Global.propColorBackground, Global.propColorBackground);
			dc.fillRectangle(bmpX, bmpY, 111, 93);

			if (screenShape == Sys.SCREEN_SHAPE_SEMI_ROUND) {
				// Time
				dc.setColor(Global.propColorForeground, Global.propColorBackground);
				dc.drawText(widthDiv2, timeY, FONT_TIME, strTime, Gfx.TEXT_JUSTIFY_CENTER);
			}
		}
		// ------------------------------------------------------------------------------------------------------------------------
		// Draw Character
		dc.drawBitmap(bmpX, bmpY, Ui.loadResource(arrAnimRezId[idxAnim]));

		return true;
	}

	// The user has just looked at their watch. Timers and animations may be started here.
	function onExitSleep() {
		tmrAnim.start(method(:timerCallback), 200, true);
	}

	// Terminate any active timers and prepare for slow updates.
	function onEnterSleep() {
		tmrAnim.stop();
		isFullRedraw = true;
		idxAnim = 0;
	}

	function timerCallback() {
		idxAnim = (idxAnim + 1) % arrAnimRezId.size();

		switch (idxAnim) {
			case 0:{
				tmrAnim.stop();
			} break;
			case 3: {
				tmrAnim.start(method(:timerCallback), 1000, false);
			} break;
			case 4: {
				tmrAnim.start(method(:timerCallback), 200, true);
			} break;
		}

		isFullRedraw = (idxAnim == 0);

		Ui.requestUpdate();
	}
}
