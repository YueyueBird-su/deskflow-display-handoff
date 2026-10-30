using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Windows.Forms;

namespace DisplayHandoffMouse {
    // RegisterHotKey runs after Deskflow's low-level hook. Remote events are
    // consumed by Deskflow; only events left on Windows reach this window.
    public sealed class LocalGestures : NativeWindow, IDisposable {
        private readonly Timer timer = new Timer();
        private readonly string statePath;
        private int pending = -1;
        private DateTime deadline;
        private int registered;
        private int localActions;
        [DllImport("user32.dll", SetLastError=true)]
        static extern bool RegisterHotKey(IntPtr window, int id, uint modifiers, uint key);
        [DllImport("user32.dll")]
        static extern bool UnregisterHotKey(IntPtr window, int id);
        [DllImport("user32.dll")]
        static extern short GetAsyncKeyState(int key);
        [StructLayout(LayoutKind.Sequential)]
        struct Keyboard { public ushort Key, Scan; public uint Flags, Time; public UIntPtr Extra; }
        [StructLayout(LayoutKind.Sequential)]
        struct Mouse { public int X,Y; public uint Data, Flags, Time; public UIntPtr Extra; }
        [StructLayout(LayoutKind.Explicit)]
        struct InputData { [FieldOffset(0)] public Keyboard Keyboard; [FieldOffset(0)] public Mouse Mouse; }
        [StructLayout(LayoutKind.Sequential)]
        struct Input { public uint Type; public InputData Data; }
        [DllImport("user32.dll", SetLastError=true)]
        static extern uint SendInput(uint count, Input[] inputs, int size);

        public LocalGestures(string directory) {
            statePath = Path.Combine(directory, "mouse-bridge-state.json");
            CreateHandle(new CreateParams { Parent = new IntPtr(-3) });
            try {
                for (int i=0; i<5; i++) {
                    if (!RegisterHotKey(Handle,100+i,0x4007,(uint)(0x7c+i))) throw new Win32Exception();
                    registered++;
                }
                timer.Interval=15;
                timer.Tick+=OnTick;
                Save("ready");
            } catch { Dispose(); throw; }
        }

        private void Save(string status) {
            try {
                File.WriteAllText(statePath,"{\"status\":\""+status+"\",\"registered\":"+registered+
                    ",\"localActions\":"+localActions+",\"at\":\""+DateTimeOffset.Now.ToString("o")+"\"}",new UTF8Encoding(false));
            } catch (IOException) { } catch (UnauthorizedAccessException) { }
        }

        protected override void WndProc(ref Message message) {
            if(message.Msg==0x312 && message.WParam.ToInt32()>=100 && message.WParam.ToInt32()<105) {
                pending=message.WParam.ToInt32()-100;
                deadline=DateTime.UtcNow.AddSeconds(1);
                timer.Start();
            }
            base.WndProc(ref message);
        }

        private void OnTick(object sender, EventArgs args) {
            if(DateTime.UtcNow>deadline){timer.Stop();pending=-1;return;}
            foreach(int key in new int[]{0x10,0x11,0x12,0x5b,0x5c,0x7c,0x7d,0x7e,0x7f,0x80})
                if((GetAsyncKeyState(key)&0x8000)!=0)return;
            timer.Stop();
            int action=pending;pending=-1;
            ushort[] keys;
            switch(action) {
                case 0: keys=new ushort[]{0x5b,0x09};break;
                case 1: keys=new ushort[]{0x11,0x5b,0x25};break;
                case 2: keys=new ushort[]{0x11,0x5b,0x27};break;
                case 3: keys=new ushort[]{0x5b};break;
                case 4: keys=new ushort[]{0x5b,0x44};break;
                default:return;
            }
            var inputs=new List<Input>();
            foreach(ushort key in keys)inputs.Add(new Input {Type=1,Data=new InputData{Keyboard=new Keyboard{Key=key,Flags=Extended(key)}}});
            for(int i=keys.Length-1;i>=0;i--)inputs.Add(new Input {Type=1,Data=new InputData{Keyboard=new Keyboard{Key=keys[i],Flags=2|Extended(keys[i])}}});
            if(SendInput((uint)inputs.Count,inputs.ToArray(),Marshal.SizeOf(typeof(Input)))!=inputs.Count) {Save("inputFailed");return;}
            localActions++;
            Save("ready");
        }

        private static uint Extended(ushort key) {return key==0x25 || key==0x27 || key==0x5b || key==0x5c ? 1u : 0u;}

        public void Dispose() {
            timer.Stop();timer.Dispose();
            if(Handle!=IntPtr.Zero){for(int i=0;i<registered;i++)UnregisterHotKey(Handle,100+i);DestroyHandle();}
        }
    }
}
