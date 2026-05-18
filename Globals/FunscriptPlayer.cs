using Godot;
using Godot.Collections;
using System;
using System.Collections.Generic;

public partial class FunscriptPlayer : Node
{
	private struct Action { public float AtMs; public int Pos; }

	private List<Action> _actions = new List<Action>();
	private bool _playing = false;
	private double _positionMs = 0.0;
	private int _actionIndex = 0;
	private bool? _isLinearDevice = null;
	private int _deviceIndex = -1;
	private bool _syncedThisFrame = false;

	public bool Playing => _playing;

	public void LoadFunscript(string path)
	{
		_actions.Clear();
		_actionIndex = 0;
		_positionMs = 0.0;
		_playing = false;
		_isLinearDevice = null;

		string absPath = ProjectSettings.GlobalizePath(path);
		using var f = FileAccess.Open(absPath, FileAccess.ModeFlags.Read);
		if (f == null) 
		{ 
			GD.PrintErr($"FunscriptPlayer: cannot open {path}"); 
			return; 
		}

		var parser = new Json();
		if (parser.Parse(f.GetAsText()) != Error.Ok)
		{
			GD.PrintErr($"FunscriptPlayer: JSON parse error in {path}");
			return;
		}

		var data = parser.Data.AsGodotDictionary();
		var raw = data.ContainsKey("actions") ? data["actions"].AsGodotArray() : new Godot.Collections.Array();
		foreach (var item in raw)
		{
			var a = item.AsGodotDictionary();
			_actions.Add(new Action
			{
				AtMs = a.ContainsKey("at") ? a["at"].AsSingle() : 0f,
				Pos = a.ContainsKey("pos") ? a["pos"].AsInt32() : 0,
			});
		}
	}

	public void Play() => _playing = true;
	public void Pause() => _playing = false;
	public void Resume() => _playing = true;

	public void Stop()
	{
		_playing = false;
		_positionMs = 0.0;
		_actionIndex = 0;
		_isLinearDevice = null;
		_deviceIndex = -1;
	}

	// Call this each frame from GameLoop to keep funscript in sync with the video clock.
	// Only updates _positionMs — _Process is responsible for dispatching due actions.
	public void SyncTo(double videoPositionSec)
	{
		_positionMs = videoPositionSec * 1000.0;
		_syncedThisFrame = true;
	}

	public override void _Process(double delta)
	{
		if (!_playing || _actions.Count == 0)
			return;

		// When synced to a video clock, SyncTo already set _positionMs this frame.
		// Only accumulate delta in free-running mode (no video / funscript-only).
		if (_syncedThisFrame)
			_syncedThisFrame = false;
		else
			_positionMs += delta * 1000.0;

		while (_actionIndex < _actions.Count)
		{
			if (_actions[_actionIndex].AtMs > _positionMs)
				break;

			SendCommand(_actionIndex);
			_actionIndex++;
		}

	}

	private void SendCommand(int index)
	{
		var bp = GetNode<ButtplugService>("/root/ButtplugService");

		if (bp == null || !bp.BpConnected)
			return;

		if (_isLinearDevice == null)
		{
			_deviceIndex = bp.GetSelectedDeviceIndex();
			_isLinearDevice = _deviceIndex >= 0 && bp.DeviceSupportsLinear(_deviceIndex);
		}

		if (_deviceIndex < 0)
			return;

		if (_isLinearDevice == true)
		{
			// Funscript actions are keyframes: at AtMs[i] the device should be at Pos[i].
			// Crossing action i means the device just reached Pos[i] — now command it
			// toward the NEXT action's position over the gap to that action.
			if (index + 1 >= _actions.Count)
				return;
			double targetNormalised = _actions[index + 1].Pos / 100.0;
			uint durationMs = (uint)Math.Max(1, (int)(_actions[index + 1].AtMs - _actions[index].AtMs));
			bp.SendLinear(_deviceIndex, durationMs, targetNormalised);
		}
		else
		{
			// Vibrators have no stroke direction — just hold the current keyframe intensity.
			bp.SendVibrate(_deviceIndex, _actions[index].Pos / 100.0);
		}
	}
}
