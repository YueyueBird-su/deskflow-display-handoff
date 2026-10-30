using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Windows.Forms;

namespace DisplayHandoff {
    public sealed class Adapter {
        public string Device, AdapterId, MonitorId, MonitorName, Mode;
        public uint Flags;
        public int X, Y, Width, Height;
    }
    public static class Native {
        [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)]
        struct DeviceInfo {
            public uint Size;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst=32)] public string Name;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst=128)] public string Description;
            public uint Flags;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst=128)] public string Id;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst=128)] public string Key;
        }
        [StructLayout(LayoutKind.Sequential)] struct Rect { public int Left,Top,Right,Bottom; }
        [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)]
        struct MonitorInfo {
            public int Size; public Rect Monitor, Work; public uint Flags;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst=32)] public string Device;
        }
        [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)]
        struct PhysicalMonitor {
            public IntPtr Handle;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst=128)] public string Description;
        }
        delegate bool MonitorCallback(IntPtr monitor, IntPtr dc, IntPtr rect, IntPtr data);
        [DllImport("user32.dll", CharSet=CharSet.Unicode, EntryPoint="EnumDisplayDevicesW")]
        static extern bool EnumDisplayDevices(string name, uint index, ref DeviceInfo info, uint flags);
        [DllImport("user32.dll", CharSet=CharSet.Unicode, EntryPoint="EnumDisplaySettingsExW")]
        static extern bool EnumDisplaySettings(string name, int mode, IntPtr data, uint flags);
        [DllImport("user32.dll", CharSet=CharSet.Unicode, EntryPoint="ChangeDisplaySettingsExW")]
        static extern int ChangeDisplaySettings(string name, IntPtr mode, IntPtr hwnd, uint flags, IntPtr param);
        [DllImport("user32.dll")] static extern bool EnumDisplayMonitors(IntPtr dc, IntPtr clip, MonitorCallback callback, IntPtr data);
        [DllImport("user32.dll", CharSet=CharSet.Unicode, EntryPoint="GetMonitorInfoW")]
        static extern bool GetMonitorInfo(IntPtr monitor, ref MonitorInfo info);
        [DllImport("dxva2.dll", SetLastError=true)] static extern bool GetNumberOfPhysicalMonitorsFromHMONITOR(IntPtr monitor, out uint count);
        [DllImport("dxva2.dll", SetLastError=true)] static extern bool GetPhysicalMonitorsFromHMONITOR(IntPtr monitor, uint count, [Out] PhysicalMonitor[] monitors);
        [DllImport("dxva2.dll")] static extern bool DestroyPhysicalMonitors(uint count, PhysicalMonitor[] monitors);
        [DllImport("dxva2.dll", SetLastError=true)] static extern bool SetVCPFeature(IntPtr monitor, byte code, uint value);
        [DllImport("dxva2.dll", SetLastError=true)] static extern bool GetVCPFeatureAndVCPFeatureReply(IntPtr monitor, byte code, out uint type, out uint current, out uint maximum);
        [DllImport("kernel32.dll")] public static extern uint WTSGetActiveConsoleSessionId();

        static DeviceInfo NewDevice() { return new DeviceInfo {Size=(uint)Marshal.SizeOf(typeof(DeviceInfo))}; }
        static byte[] ReadMode(string name) {
            IntPtr ptr=Marshal.AllocHGlobal(220);
            try {
                Marshal.Copy(new byte[220],0,ptr,220);
                Marshal.WriteInt16(ptr,68,220);
                if(!EnumDisplaySettings(name,-1,ptr,0) && !EnumDisplaySettings(name,-2,ptr,0)) return null;
                byte[] bytes=new byte[220]; Marshal.Copy(ptr,bytes,0,220); return bytes;
            } finally {Marshal.FreeHGlobal(ptr);}
        }
        public static Adapter[] Adapters() {
            var list=new List<Adapter>();
            for(uint index=0;;index++) {
                var device=NewDevice(); if(!EnumDisplayDevices(null,index,ref device,0)) break;
                if((device.Flags & 8)!=0) continue;
                var monitor=NewDevice(); EnumDisplayDevices(device.Name,0,ref monitor,1);
                var mode=ReadMode(device.Name);
                list.Add(new Adapter {
                    Device=device.Name,AdapterId=device.Id,MonitorId=monitor.Id,MonitorName=monitor.Description,Flags=device.Flags,
                    Mode=mode==null?null:Convert.ToBase64String(mode),
                    X=mode==null?0:BitConverter.ToInt32(mode,76),Y=mode==null?0:BitConverter.ToInt32(mode,80),
                    Width=mode==null?0:BitConverter.ToInt32(mode,172),Height=mode==null?0:BitConverter.ToInt32(mode,176)
                });
            }
            return list.ToArray();
        }
        static void ModeChange(string device, string encoded, bool detach, uint flags) {
            byte[] mode=Convert.FromBase64String(encoded);
            if(mode.Length!=220) throw new InvalidOperationException("Invalid saved display mode.");
            IntPtr ptr=Marshal.AllocHGlobal(220);
            try {
                Marshal.Copy(mode,0,ptr,220); Marshal.WriteInt16(ptr,68,220);
                if(detach) {
                    Marshal.WriteInt32(ptr,72,0x180020); // Position plus zero width/height; required by this display driver.
                    Marshal.WriteInt32(ptr,172,0); Marshal.WriteInt32(ptr,176,0);
                }
                int result=ChangeDisplaySettings(device,ptr,IntPtr.Zero,flags,IntPtr.Zero);
                if(result!=0) throw new InvalidOperationException("Display mode result "+result+" for "+device);
            } finally {Marshal.FreeHGlobal(ptr);}
        }
        public static void ApplyRight(string device,string mode,bool detach) {
            // Update only the shared right display. The left display is never disabled.
            ModeChange(device,mode,detach,0x10000001); // CDS_NORESET | CDS_UPDATEREGISTRY
            int result=ChangeDisplaySettings(null,IntPtr.Zero,IntPtr.Zero,0,IntPtr.Zero);
            if(result!=0) throw new InvalidOperationException("Apply display result "+result);
        }
        public static void TestRestore(string device,string mode) { ModeChange(device,mode,false,2); }
        public static int Input(string device,int value) {
            int reply=-1; Exception failure=null; bool found=false;
            MonitorCallback callback=delegate(IntPtr handle,IntPtr dc,IntPtr rect,IntPtr data) {
                var info=new MonitorInfo {Size=Marshal.SizeOf(typeof(MonitorInfo))};
                if(!GetMonitorInfo(handle,ref info) || info.Device!=device) return true;
                found=true;
                uint count;
                if(!GetNumberOfPhysicalMonitorsFromHMONITOR(handle,out count) || count!=1) {
                    failure=new InvalidOperationException("Expected one physical shared monitor."); return false;
                }
                var monitors=new PhysicalMonitor[count];
                if(!GetPhysicalMonitorsFromHMONITOR(handle,count,monitors)) {failure=new Win32Exception();return false;}
                try {
                    if(value>=0 && !SetVCPFeature(monitors[0].Handle,0x60,(uint)value)) throw new Win32Exception();
                    uint type,current=0,maximum;
                    bool read=false;
                    for(int attempt=0;attempt<(value>=0?15:1);attempt++) {
                        if(value>=0)System.Threading.Thread.Sleep(150);
                        read=GetVCPFeatureAndVCPFeatureReply(monitors[0].Handle,0x60,out type,out current,out maximum);
                        if(read && (value<0 || (current & 255)==value))break;
                    }
                    if(!read)throw new Win32Exception();
                    if(value>=0 && (current & 255)!=value)throw new InvalidOperationException("Input source did not confirm requested value.");
                    reply=(int)current;
                } catch(Exception ex) {failure=ex;}
                finally {DestroyPhysicalMonitors(count,monitors);}
                return false;
            };
            EnumDisplayMonitors(IntPtr.Zero,IntPtr.Zero,callback,IntPtr.Zero);
            if(failure!=null) throw failure;
            if(!found) throw new InvalidOperationException("Shared display is not active.");
            return reply;
        }
        [StructLayout(LayoutKind.Sequential)] struct KeyboardInput {public ushort Key,Scan;public uint Flags,Time;public UIntPtr Extra;}
        [StructLayout(LayoutKind.Sequential)] struct MouseInput {public int X,Y;public uint Data,Flags,Time;public UIntPtr Extra;}
        [StructLayout(LayoutKind.Explicit)] struct InputUnion {
            [FieldOffset(0)]public KeyboardInput Keyboard;[FieldOffset(0)]public MouseInput Mouse;
        }
        [StructLayout(LayoutKind.Sequential)] struct InputRecord {public uint Type;public InputUnion Union;}
        [DllImport("user32.dll",SetLastError=true)]static extern uint SendInput(uint count,InputRecord[] inputs,int size);
        public static void Signal(int functionNumber) {
            if(functionNumber!=22 && functionNumber!=23)throw new ArgumentException("Invalid control signal.");
            ushort[] keys={0x11,0x12,0x10,(ushort)(0x6f+functionNumber)};
            var inputs=new List<InputRecord>();
            foreach(var key in keys)inputs.Add(new InputRecord {Type=1,Union=new InputUnion {Keyboard=new KeyboardInput {Key=key}}});
            for(int i=keys.Length-1;i>=0;i--)inputs.Add(new InputRecord {Type=1,Union=new InputUnion {Keyboard=new KeyboardInput {Key=keys[i],Flags=2}}});
            if(SendInput((uint)inputs.Count,inputs.ToArray(),Marshal.SizeOf(typeof(InputRecord)))!=inputs.Count)throw new Win32Exception();
        }
    }
    public sealed class HotkeyWindow : NativeWindow, IDisposable {
        const int WM_HOTKEY=0x312, WM_MODE=0x8002, WM_REFRESH=0x8003;
        readonly Action<int> callback;
        readonly System.Threading.ManualResetEvent hookReady=new System.Threading.ManualResetEvent(false);
        readonly HashSet<int> held=new HashSet<int>();
        delegate IntPtr HookProc(int code,IntPtr message,IntPtr data);
        readonly HookProc mediaHandler;
        System.Threading.Thread mediaThread; uint mediaThreadId; IntPtr hook;
        Exception hookError;
        [StructLayout(LayoutKind.Sequential)]struct NativeMessage {
            public IntPtr Window;public uint Message;public UIntPtr Word;public IntPtr Data;
            public uint Time;public int X,Y;public uint Private;
        }
        [DllImport("user32.dll",SetLastError=true)]static extern bool RegisterHotKey(IntPtr window,int id,uint modifiers,uint key);
        [DllImport("user32.dll")]static extern bool UnregisterHotKey(IntPtr window,int id);
        [DllImport("user32.dll",SetLastError=true)]static extern IntPtr SetWindowsHookEx(int id,HookProc callback,IntPtr module,uint thread);
        [DllImport("user32.dll")]static extern bool UnhookWindowsHookEx(IntPtr value);
        [DllImport("user32.dll")]static extern IntPtr CallNextHookEx(IntPtr value,int code,IntPtr message,IntPtr data);
        [DllImport("user32.dll")]static extern bool PostMessage(IntPtr window,int message,IntPtr word,IntPtr data);
        [DllImport("user32.dll")]static extern bool PostThreadMessage(uint thread,uint message,IntPtr word,IntPtr data);
        [DllImport("user32.dll")]static extern int GetMessage(out NativeMessage message,IntPtr window,uint first,uint last);
        [DllImport("user32.dll")]static extern bool PeekMessage(out NativeMessage message,IntPtr window,uint first,uint last,uint remove);
        [DllImport("user32.dll")]static extern bool TranslateMessage(ref NativeMessage message);
        [DllImport("user32.dll")]static extern IntPtr DispatchMessage(ref NativeMessage message);
        [DllImport("kernel32.dll",CharSet=CharSet.Unicode)]static extern IntPtr GetModuleHandle(string name);
        [DllImport("kernel32.dll")]static extern uint GetCurrentThreadId();
        public HotkeyWindow(Action<int> action) {
            callback=action;CreateHandle(new CreateParams {Parent=new IntPtr(-3)});
            mediaHandler=OnMedia;
            if(!RegisterHotKey(Handle,1,0x4007,0x83) || !RegisterHotKey(Handle,2,0x4007,0x84)) {
                Dispose();throw new Win32Exception("Display helper hotkey registration failed.");
            }
            mediaThread=new System.Threading.Thread(MediaLoop);mediaThread.IsBackground=true;mediaThread.Start();
            if(!hookReady.WaitOne(5000) || hookError!=null) {Dispose();throw new InvalidOperationException("Media key hook did not start.",hookError);}
        }
        void InstallMediaHook() {
            if(hook!=IntPtr.Zero)UnhookWindowsHookEx(hook);
            hook=SetWindowsHookEx(13,mediaHandler,GetModuleHandle(null),0);
            if(hook==IntPtr.Zero)throw new Win32Exception();
        }
        void MediaLoop() {
            try {
                NativeMessage message;PeekMessage(out message,IntPtr.Zero,0,0,0);
                mediaThreadId=GetCurrentThreadId();InstallMediaHook();hookReady.Set();
                while(GetMessage(out message,IntPtr.Zero,0,0)>0) {
                    if(message.Message==WM_REFRESH)InstallMediaHook();
                    else {TranslateMessage(ref message);DispatchMessage(ref message);}
                }
            } catch(Exception error) {hookError=error;hookReady.Set();}
            finally {if(hook!=IntPtr.Zero){UnhookWindowsHookEx(hook);hook=IntPtr.Zero;}}
        }
        IntPtr OnMedia(int code,IntPtr message,IntPtr data) {
            if(code>=0) {
                int key=Marshal.ReadInt32(data);
                // The two physical keys were verified with the user. No text keys are recorded.
                if(key==0xB5 || key==0xB4) {
                    int kind=message.ToInt32();
                    if(kind==0x100 || kind==0x104) {
                        if(held.Add(key))PostMessage(Handle,WM_MODE,new IntPtr(key==0xB5?1:2),IntPtr.Zero);
                        return new IntPtr(1);
                    }
                    if(kind==0x101 || kind==0x105){held.Remove(key);return new IntPtr(1);}
                }
            }
            return CallNextHookEx(hook,code,message,data);
        }
        public void RefreshMediaHook() {
            if(hookError!=null)throw new InvalidOperationException("Media key thread stopped.",hookError);
            if(mediaThreadId!=0)PostThreadMessage(mediaThreadId,WM_REFRESH,IntPtr.Zero,IntPtr.Zero);
        }
        protected override void WndProc(ref Message message) {
            if(message.Msg==WM_HOTKEY || message.Msg==WM_MODE)callback(message.WParam.ToInt32());
            base.WndProc(ref message);
        }
        public void Dispose() {
            if(mediaThreadId!=0)PostThreadMessage(mediaThreadId,0x12,IntPtr.Zero,IntPtr.Zero);
            if(mediaThread!=null)mediaThread.Join(1500);
            if(Handle!=IntPtr.Zero){UnregisterHotKey(Handle,1);UnregisterHotKey(Handle,2);DestroyHandle();}
            hookReady.Dispose();
        }
    }
}
