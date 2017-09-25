class DelayedEvac_GameState_EvacZoneSpawner extends XComGameState_BaseObject
	config(DelayedEvac);

var() protectedwrite Vector CenterLocationV;
var config int EvacCountdownTurns;
var config int EvacCallCooldownTurns;
var config int ExclusionRadius;
var config bool ExclusionRadiusVisible;

// The number of player turns remaining before the zone spawns
var int Countdown;
var() protectedwrite ETeam Team;

static function DelayedEvac_GameState_EvacZoneSpawner PlaceEvacZoneSpawner(
	XComGameState NewGameState,
  Vector SpawnLocation,
  optional ETeam InTeam = eTeam_XCom
)	{
	local XComGameState_EvacZone EvacState;
	local DelayedEvac_GameState_EvacZoneSpawner SpawnerState;
	local X2Actor_EvacZone EvacZoneActor;

	EvacState = GetEvacZone(InTeam);
	if (EvacState != none)
	{
		EvacZoneActor = X2Actor_EvacZone( EvacState.GetVisualizer( ) );
		if (EvacZoneActor != none)
		{
			EvacZoneActor.Destroy( );
		}

		NewGameState.RemoveStateObject(EvacState.ObjectID);
	}

	SpawnerState = DelayedEvac_GameState_EvacZoneSpawner(NewGameState.CreateStateObject(class'DelayedEvac_GameState_EvacZoneSpawner'));
	SpawnerState.Team = InTeam;

	SpawnerState.Countdown = default.EvacCountdownTurns * 2;
	SpawnerState.CenterLocationV = SpawnLocation;
	NewGameState.AddStateObject(SpawnerState);
	`log("DelayedEvac : Placing Evac Zone Spawner at " @ SpawnLocation);

	SpawnerState.RegisterListener();

	return SpawnerState;
}

function OnEndTacticalPlay(XComGameState NewGameState)
{
	local X2EventManager EventManager;
	local Object ThisObj;

	super.OnEndTacticalPlay(NewGameState);

	EventManager = `XEVENTMGR;
	ThisObj = self;
	EventManager.UnRegisterFromEvent(ThisObj, 'PlayerTurnBegun');
}


function RegisterListener () {
	local Object ThisObj;
	ThisObj = self;
	`XEVENTMGR.RegisterForEvent(ThisObj, 'PlayerTurnBegun', OnTurnBegun, ELD_OnStateSubmitted);
}

// This is called at the start of each AI turn
function EventListenerReturn OnTurnBegun(Object EventData, Object EventSource, XComGameState GameState, Name EventID, Object CallbackData)
{
	local XComGameState NewGameState;
	local X2GameRuleset Ruleset;
	local DelayedEvac_GameState_EvacZoneSpawner NewSpawnerState;
	local Object ThisObj;
	ThisObj = self;

	Ruleset = `XCOMGAME.GameRuleset;
	`log("DelayedEvac :: Countdown - " @ Countdown);

	if( Countdown > 0 )
	{
		NewGameState = class'XComGameStateContext_ChangeContainer'.static.CreateChangeState("UpdateEvacCountdown");
		NewSpawnerState = DelayedEvac_GameState_EvacZoneSpawner(NewGameState.CreateStateObject(class'DelayedEvac_GameState_EvacZoneSpawner', ObjectID));
		--NewSpawnerState.Countdown;

		if( NewSpawnerState.Countdown == 0 )
		{
			NewGameState.RemoveStateObject(NewSpawnerState.ObjectID);

			`log("DelayedEvac :: Spawning Evac Zone at " @ CenterLocationV);
			if (EvacPointValid(CenterLocationV))
			{
				class'XComGameState_EvacZone'.static.PlaceEvacZone(NewGameState, CenterLocationV, Team);
				XComGameStateContext_ChangeContainer(NewGameState.GetContext()).BuildVisualizationFn = BuildVisualizationForEvacSuccess;
			}
			else
			{
				XComGameStateContext_ChangeContainer(NewGameState.GetContext()).BuildVisualizationFn = BuildVisualizationForEvacTooHot;
			}

			Ruleset.SubmitGameState(NewGameState);
			`XEVENTMGR.UnRegisterFromEvent(ThisObj, 'PlayerTurnBegun');
		} else {
			NewGameState.AddStateObject(NewSpawnerState);
			Ruleset.SubmitGameState(NewGameState);
		}

	}

	return ELR_NoInterrupt;
}


static function XComGameState_EvacZone GetEvacZone(optional ETeam InTeam = eTeam_XCom)
{
	local XComGameState_EvacZone EvacState;
	local XComGameStateHistory History;

	History = `XCOMHISTORY;
	foreach History.IterateByClassType(class'XComGameState_EvacZone', EvacState)
	{
		if(EvacState.Team == InTeam)
		{
			return EvacState;
		}
	}

	return none;
}


function bool EvacPointValid(vector CenterLoc)
{
	local XComWorldData WorldData;
	local XComGameStateHistory History;
	local XComGameState_Unit Unit;
	local TTile UnitTileLocation, CenterTile;
	local float Distance, Ax, Bx, Cx;

	if (default.ExclusionRadius == 0)
	{
		return true;
	}

	History = `XCOMHISTORY;
	WorldData = `XWORLD;
	if(!WorldData.GetFloorTileForPosition(CenterLoc, CenterTile))
	{
		CenterTile = WorldData.GetTileCoordinatesFromPosition(CenterLoc);
	}

	foreach History.IterateByClassType(class'XComGameState_Unit', Unit)
	{
		if( Unit.GetTeam() == eTeam_Alien && Unit.IsAlive() && !Unit.bRemovedFromPlay && !Unit.IsIncapacitated() )
		{
			Unit.GetKeystoneVisibilityLocation(UnitTileLocation);
			Ax = Square(float(UnitTileLocation.X - CenterTile.X));
			Bx = Square(float(UnitTileLocation.Y - CenterTile.Y));
			Cx = Ax + Bx;
			Distance = Sqrt(Cx);
			// Sitting on this, need to figure out a good way to make it not exploitable
			`log("Enemy Proximity:" @ Distance @ " - " @ (UnitTileLocation.X - CenterTile.X) @ (UnitTileLocation.Y - CenterTile.Y));
			if (Distance < default.ExclusionRadius)
			{
				return false;
			}
		}
	}

	return true;
}


function SetupFlarePlacementNarrative(
	XComGameState GameState,
	DelayedEvac_GameState_EvacZoneSpawner SpawnerState,
	X2Action ParentAction)
{
	local VisualizationActionMetadata ActionMetadata;
	local array<string> NarrativePaths;
	local string NarrativePath;
	local XComNarrativeMoment NarrativeMoment;
	local X2Action_PlayNarrative Narrative;

	NarrativePaths.AddItem("DelayedEvac_Assets.DelayedEvac_Confirmed_Firebrand_01");
	NarrativePaths.AddItem("DelayedEvac_Assets.DelayedEvac_Confirmed_Firebrand_02");

	NarrativePath = NarrativePaths[Rand(2)];

	ActionMetadata.StateObject_OldState = SpawnerState;
	ActionMetadata.StateObject_NewState = SpawnerState;

	NarrativeMoment = XComNarrativeMoment(DynamicLoadObject(NarrativePath, class'XComNarrativeMoment'));
	Narrative = X2Action_PlayNarrative( class'X2Action_PlayNarrative'.static.AddToVisualizationTree(ActionMetadata, GameState.GetContext(), false, ParentAction) );

	Narrative.Moment = NarrativeMoment;
	Narrative.WaitForCompletion = false;
	Narrative.StopExistingNarrative = false;
}

function SetupEvacTooHotNarrative(
	XComGameState GameState,
	DelayedEvac_GameState_EvacZoneSpawner SpawnerState
) {
	local VisualizationActionMetadata ActionMetadata;
	local array<string> NarrativePaths;
	local string NarrativePath;
	local XComNarrativeMoment NarrativeMoment;
	local X2Action_PlayNarrative Narrative;

	NarrativePaths.AddItem("X2NarrativeMoments.TACTICAL.RescueVIP.CEN_RescGEN_ProceedToSweep");
	NarrativePaths.AddItem("X2NarrativeMoments.TACTICAL.RescueVIP.CEN_RescGEN_HeavyLosses");

	NarrativePath = NarrativePaths[Rand(2)];

	ActionMetadata.StateObject_OldState = SpawnerState;
	ActionMetadata.StateObject_NewState = SpawnerState;

	NarrativeMoment = XComNarrativeMoment(DynamicLoadObject(NarrativePath, class'XComNarrativeMoment'));
	Narrative = X2Action_PlayNarrative( class'X2Action_PlayNarrative'.static.AddToVisualizationTree( ActionMetadata, GameState.GetContext() ) );

	Narrative.Moment = NarrativeMoment;
	Narrative.WaitForCompletion = false;
	Narrative.StopExistingNarrative = false;
}


function SetupExclusionRing(XComGameState VisualizeGameState, bool IsActive)
{
	local VisualizationActionMetadata ActionMetadata;
	local int ix, Steps;
	local float Radius, Arc;
	local Vector EffectVector;
	local X2Action_PlayEffect EvacSpawnerEffectAction;
	Steps = 16;
	Radius = `XWORLD.WORLD_StepSize * default.ExclusionRadius;

	for (ix=0; ix < Steps; ix++) {
		Arc = 2 * Pi / Steps * Ix ;
		EffectVector = CenterLocationV;
		EffectVector.x = CenterLocationV.x + Radius * Cos(Arc);
		EffectVector.y = CenterLocationV.y + Radius * Sin(Arc);
		EvacSpawnerEffectAction = X2Action_PlayEffect(
      class'X2Action_PlayEffect'.static.AddToVisualizationTree(
        ActionMetadata, VisualizeGameState.GetContext()
      )
    );

		EvacSpawnerEffectAction.EffectName = "DelayedEvac_Assets.DelayedEvac_WarmupFlare";
		EvacSpawnerEffectAction.EffectLocation = EffectVector;
		EvacSpawnerEffectAction.CenterCameraOnEffectDuration = 0;
		EvacSpawnerEffectAction.bStopEffect = !IsActive;
	}
}

function BuildVisualizationForSpawnerCreation(XComGameState VisualizeGameState, X2Action ParentAction)
{
	local VisualizationActionMetadata ActionMetadata;
	local DelayedEvac_GameState_EvacZoneSpawner SpawnerState;
	local X2Action_PlayEffect EvacSpawnerEffectAction;

	SpawnerState = DelayedEvac_GameState_EvacZoneSpawner(`XCOMHISTORY.GetGameStateForObjectID(ObjectID));

	if (Countdown <= 0)
	{
		return; // we've completed the evac spawn
	}

	EvacSpawnerEffectAction = X2Action_PlayEffect( class'X2Action_PlayEffect'.static.AddToVisualizationTree(ActionMetadata, VisualizeGameState.GetContext(), false, ParentAction) );

	EvacSpawnerEffectAction.EffectName = "DelayedEvac_Assets.DelayedEvac_WarmupFlare";
	EvacSpawnerEffectAction.EffectLocation = CenterLocationV;
	EvacSpawnerEffectAction.CenterCameraOnEffectDuration = 0;
	EvacSpawnerEffectAction.bStopEffect = false;

	ActionMetadata.StateObject_OldState = SpawnerState;
	ActionMetadata.StateObject_NewState = SpawnerState;

	if (default.ExclusionRadius != 0 && default.ExclusionRadiusVisible)
	{
		SetupExclusionRing(VisualizeGameState, true);
	}

	SetupFlarePlacementNarrative(VisualizeGameState, SpawnerState, ParentAction);
	`log("DelayedEvac : Building Spawn Effect");
}

function BuildVisualizationForEvacSuccess(XComGameState VisualizeGameState)
{
	local VisualizationActionMetadata SpawnerMetadata, SyncMetadata;
	local XComGameState_EvacZone EvacZone;
	local DelayedEvac_GameState_EvacZoneSpawner SpawnerState;
	local X2Action_PlayEffect EvacSpawnerEffectAction;

	SpawnerState = DelayedEvac_GameState_EvacZoneSpawner(`XCOMHISTORY.GetGameStateForObjectID(ObjectID));

	if (Countdown <= 0)
	{
		return; // we've completed the evac spawn
	}

	SpawnerMetadata.StateObject_OldState = SpawnerState;
	SpawnerMetadata.StateObject_NewState = SpawnerState;

	EvacSpawnerEffectAction = X2Action_PlayEffect( class'X2Action_PlayEffect'.static.AddToVisualizationTree( SpawnerMetadata, VisualizeGameState.GetContext() ) );

	EvacSpawnerEffectAction.EffectName = "DelayedEvac_Assets.DelayedEvac_WarmupFlare";
	EvacSpawnerEffectAction.EffectLocation = CenterLocationV;
	EvacSpawnerEffectAction.bStopEffect = true;

	if (default.ExclusionRadius != 0 && default.ExclusionRadiusVisible)
	{
		SetupExclusionRing(VisualizeGameState, false);
	}

	`log("DelayedEvac : Clearing Spawn Effect, Spawning Evac Zone");

	foreach VisualizeGameState.IterateByClassType(class'XComGameState_EvacZone', EvacZone)
	{	
		SyncMetadata.StateObject_OldState = EvacZone;
		SyncMetadata.StateObject_NewState = EvacZone;
		class'X2Action_SyncVisualizer'.static.AddToVisualizationTree(SyncMetadata, VisualizeGameState.GetContext());
	}
}

function BuildVisualizationForEvacTooHot(XComGameState VisualizeGameState)
{
	local VisualizationActionMetadata ActionMetadata;
	local DelayedEvac_GameState_EvacZoneSpawner SpawnerState;
	local X2Action_PlayEffect EvacSpawnerEffectAction;

	SpawnerState = DelayedEvac_GameState_EvacZoneSpawner(`XCOMHISTORY.GetGameStateForObjectID(ObjectID));

	ActionMetadata.StateObject_OldState = SpawnerState;
	ActionMetadata.StateObject_NewState = SpawnerState;

	EvacSpawnerEffectAction = X2Action_PlayEffect( class'X2Action_PlayEffect'.static.AddToVisualizationTree(ActionMetadata, VisualizeGameState.GetContext() ) );

	EvacSpawnerEffectAction.EffectName = "DelayedEvac_Assets.DelayedEvac_WarmupFlare";
	EvacSpawnerEffectAction.EffectLocation = CenterLocationV;
	EvacSpawnerEffectAction.bStopEffect = true;

	if (default.ExclusionRadius != 0 && default.ExclusionRadiusVisible)
	{
		SetupExclusionRing(VisualizeGameState, false);
	}
	
	SetupEvacTooHotNarrative(VisualizeGameState, SpawnerState);
	`log("DelayedEvac : Clearing Spawn Effect, Declaring Zone Too Hot");
}


DefaultProperties
{
	Team=eTeam_XCom
}
