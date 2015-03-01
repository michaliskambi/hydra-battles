{
  Copyright 2015-2015 Michalis Kamburelis.

  This file is part of "Hydra Battles".

  "Hydra Battles" is free software; see the file COPYING.txt,
  included in this distribution, for details about the copyright.

  "Hydra Battles" is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

  ----------------------------------------------------------------------------
}

{ Game state to play actual game. }
unit GameStatePlay;

interface

uses Classes, FGL,
  CastleConfig, CastleKeysMouse, CastleControls, Castle2DSceneManager,
  GameStates, GameMap, GameNpcs, GamePath;

type
  { Currently drawn paths with mouse / touch device. Support multi-touch
    (crucial for our game to enable 2 players simultaneously drawing paths)
    by supporting multiple paths, for different finger index. }
  TCurrentPaths = specialize TFPGMap<TFingerIndex, TPath>;

  TStatePlay = class(TState)
  private
    Status: TCastleLabel;
    Props: TProps;
    Map: TMap;
    Npcs: TNpcs;
    CurrentPaths: TCurrentPaths;
  public
    StartMapName: string;
    constructor Create(AOwner: TComponent); override;
    procedure Start; override;
    procedure Finish; override;
    procedure Resize; override;
    procedure Update(const SecondsPassed: Single); override;
    procedure Press(const Event: TInputPressRelease); override;
    procedure Release(const Event: TInputPressRelease); override;
    procedure Motion(const Event: TInputMotion); override;
    procedure GLContextOpen; override;
    procedure GLContextClose; override;
  end;

var
  StatePlay: TStatePlay;

implementation

uses SysUtils,
  CastleScene, CastleVectors, CastleFilesUtils, CastleSceneCore,
  CastleColors, CastleUIControls, CastleUtils, CastleGLUtils,
  CastleGLImages, CastleStringUtils, CastleRectangles,
  GameUtils, GameStateMainMenu;

{ TStatePlay ----------------------------------------------------------------- }

constructor TStatePlay.Create(AOwner: TComponent);
begin
  inherited;
end;

procedure TStatePlay.Start;
begin
  inherited;

  GameTime := 0;

  CurrentPaths := TCurrentPaths.Create;

  Props := TProps.Create;
  Npcs := TNpcs.Create;
  Map := TMap.Create(StartMapName, Props, Npcs);
  Window.Controls.InsertFront(Map);

  VisualizationSceneManager := T2DSceneManager.Create(Self);
  VisualizationSceneManager.FullSize :=false;
  VisualizationSceneManager.Transparent := true;
  Window.Controls.InsertFront(VisualizationSceneManager);

  Status := TCastleLabel.Create(Self);
  Status.Padding := 5;
  Status.Color := White;
  Status.Left := 10;
  Status.Bottom := 10;
  Status.Frame := false;
  Status.Alignment := prRight;
  Window.Controls.InsertFront(Status);
end;

procedure TStatePlay.Finish;
begin
  FreeAndNil(Status);
  FreeAndNil(VisualizationSceneManager);
  FreeAndNil(Map);
  FreeAndNil(Props);
  FreeAndNil(Npcs);
  FreeAndNil(CurrentPaths);
  inherited;
end;

procedure TStatePlay.Resize;
var
  R: TRectangle;
begin
  inherited;

  R := Map.Rect;
  VisualizationSceneManager.Left := R.Left;
  VisualizationSceneManager.Bottom := R.Bottom;
  VisualizationSceneManager.Width := R.Width;
  VisualizationSceneManager.Height := R.Height;
end;

procedure TStatePlay.Update(const SecondsPassed: Single);
var
  S: string;
begin
  inherited;

  S := Format('FPS: %f real : %f', [Window.Fps.FrameTime, Window.Fps.RealTime]);
  Status.Text.Text := S;
  Status.AlignHorizontal(prRight, prRight);
  Status.AlignVertical(prTop, prTop);

  GameTime += SecondsPassed;

  Window.Invalidate;
end;

procedure TStatePlay.Press(const Event: TInputPressRelease);
var
  PT: TPropType;
  Prop: TProp;
  RandomMountain: char;
  NewPath: TPath;
  PathStartX, PathStartY: Integer;
begin
  inherited;
  if Event.IsKey('E') then
    Map.EditMode := not Map.EditMode;
  if Event.IsKey('G') then
    Map.Grid := not Map.Grid;

  if Map.EditMode then
  begin
    if Event.IsKey(K_Up) then
      Map.EditCursor[1] := Map.EditCursor[1] + 1;
    if Event.IsKey(K_Down) then
      Map.EditCursor[1] := Map.EditCursor[1] - 1;
    if Event.IsKey(K_Right) then
      Map.EditCursor[0] := Map.EditCursor[0] + 1;
    if Event.IsKey(K_Left) then
      Map.EditCursor[0] := Map.EditCursor[0] - 1;
    Map.EditCursor[0] := Clamped(Map.EditCursor[0], 0, Map.Width - 1);
    Map.EditCursor[1] := Clamped(Map.EditCursor[1], 0, Map.Height - 1);
    for PT := Low(PT) to High(PT) do
    begin
      Prop := Props[PT];
      if Event.IsKey(Prop.EditorShortcut) then
        Map.MapProps[Map.EditCursor[0], Map.EditCursor[1]] := Prop;
    end;
    if Event.IsKey('0') then
    begin
      RandomMountain := Chr(Random(8) + Ord('1'));
      for PT := Low(PT) to High(PT) do
      begin
        Prop := Props[PT];
        if Prop.EditorShortcut = RandomMountain then
          Map.MapProps[Map.EditCursor[0], Map.EditCursor[1]] := Prop;
      end;
    end;
    if Event.IsKey(' ') then
      Map.MapProps[Map.EditCursor[0], Map.EditCursor[1]] := nil;
    if Event.IsKey('S') then
      Map.SaveToFile;
    if Event.IsKey('N') then
    begin
      Map.SetNpcInstance(Map.EditCursor[0], Map.EditCursor[1],
        TNpcInstance.Create(Npcs.Npcs[RandomFaction, RandomNpcType], RandomDirection));
    end;
  end;

  if Event.IsMouseButton(mbLeft) then
  begin
    if Map.PositionToTile(Map.Rect, Event.Position, PathStartX, PathStartY) and
       (Map.MapNpcs[PathStartX, PathStartY] <> nil) then
    begin
      NewPath := TPath.Create(Map, PathStartX, PathStartY);
      CurrentPaths[Event.FingerIndex] := NewPath;
      Map.MapNpcs[PathStartX, PathStartY].Path := NewPath;
    end;
  end;
end;

procedure TStatePlay.Release(const Event: TInputPressRelease);
begin
  inherited;
  if Event.IsMouseButton(mbLeft) then
    CurrentPaths.Remove(Event.FingerIndex);
end;

procedure TStatePlay.Motion(const Event: TInputMotion);

  { Remove (freeing) current Path, under Event.FingerIndex. }
  procedure BreakPath(const Path: TPath);
  var
    I: Integer;
  begin
    CurrentPaths.Remove(Event.FingerIndex);
    for I := 0 to Map.NpcInstances.Count - 1 do
      if Map.NpcInstances[I].Path = Path then
        Map.NpcInstances[I].Path := nil;
  end;

var
  X, Y, PathUnderFingerIndex: Integer;
  MapRect: TRectangle;
  CurrentPath: TPath;
begin
  inherited;
  PathUnderFingerIndex := CurrentPaths.IndexOf(Event.FingerIndex);
  if PathUnderFingerIndex <> -1 then
  begin
    CurrentPath := CurrentPaths.Data[PathUnderFingerIndex];
    MapRect := Map.Rect;
    if not Map.PositionToTile(MapRect, Event.Position, X, Y) then
      BreakPath(CurrentPath) else
    begin
      Map.EditCursor[0] := X;
      Map.EditCursor[1] := Y;
      if not CurrentPath.Add(X, Y) then
        BreakPath(CurrentPath);
    end;
  end;
end;

procedure TStatePlay.GLContextOpen;
begin
  inherited;
  Props.GLContextOpen;
  Npcs.GLContextOpen;
end;

procedure TStatePlay.GLContextClose;
begin
  if Props <> nil then
    Props.GLContextClose;
  if Npcs <> nil then
    Npcs.GLContextClose;
  inherited;
end;

end.
