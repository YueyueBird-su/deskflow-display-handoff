using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Windows.Forms;
namespace DisplayHandoffProbe {
    public sealed class ProbeWindow:NativeWindow,IDisposable {
        delegate IntPtr HookProc(int code,IntPtr message,IntPtr data);
        readonly HookProc handler;readonly Action<int> callback;
        readonly HashSet<int> held=new HashSet<int>();IntPtr hook;
        [DllImport("user32.dll",SetLastError=true)]static extern IntPtr SetWindowsHookEx(int id,HookProc callback,IntPtr module,uint thread);
        [DllImport("user32.dll")]static extern bool UnhookWindowsHookEx(IntPtr hook);
        [DllImport("user32.dll")]static extern IntPtr CallNextHookEx(IntPtr hook,int code,IntPtr message,IntPtr data);
        [DllImport("user32.dll")]static extern bool PostMessage(IntPtr window,int message,IntPtr word,IntPtr data);
        [DllImport("kernel32.dll",CharSet=CharSet.Unicode)]static extern IntPtr GetModuleHandle(string name);
        public ProbeWindow(Action<int> action) {
            callback=action;CreateHandle(new CreateParams {Parent=new IntPtr(-3)});
            handler=OnKeyboard;hook=SetWindowsHookEx(13,handler,GetModuleHandle(null),0);
            if(hook==IntPtr.Zero)throw new System.ComponentModel.Win32Exception();
        }
        IntPtr OnKeyboard(int code,IntPtr message,IntPtr data) {
            if(code>=0) {
                int key=Marshal.ReadInt32(data);
                // Only media/application-launch function keys; never inspect text input.
                if(key>=0xB0 && key<=0xB7) {
                    int kind=message.ToInt32();
                    if(kind==0x100 || kind==0x104) {
                        if(held.Add(key))PostMessage(Handle,0x8001,new IntPtr(key),IntPtr.Zero);
                        return new IntPtr(1);
                    }
                    if(kind==0x101 || kind==0x105){held.Remove(key);return new IntPtr(1);}
                }
            }
            return CallNextHookEx(hook,code,message,data);
        }
        protected override void WndProc(ref Message message) {
            if(message.Msg==0x8001)callback(message.WParam.ToInt32());
            base.WndProc(ref message);
        }
        public void Dispose(){if(hook!=IntPtr.Zero){UnhookWindowsHookEx(hook);hook=IntPtr.Zero;}if(Handle!=IntPtr.Zero)DestroyHandle();}
    }
}
