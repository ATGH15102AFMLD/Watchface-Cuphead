using Toybox.Application as App;
using Toybox.WatchUi as Ui;
using Toybox.System as Sys;

class CupheadApp extends App.AppBase {

	function initialize() {
		AppBase.initialize();
	}

	// Return the initial view of your application here
	function getInitialView() {
		return [new CupheadView()];
	}

	// New app settings have been received so trigger a UI update
	function onSettingsChanged() {
		Global.handlSettingUpdate();
		Ui.requestUpdate();
	}

	// This method runs when a goal is triggered and the goal view is started.
	function getGoalView(goal) {
		return null;
	}

}
