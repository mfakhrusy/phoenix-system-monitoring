This is just a simple project that combines

1. Elixir/Phoenix
2. libvirt C API
3. Erlang NIF to bridge C -> Phoenix LiveView



Current features

1. Shows Host CPU percentage (using delta of cpu time per second)
2. Shows virtual machine states
3. Shutdown VM via browser (The "Start" button still not working as of this commit)

Limitations

1. Only works on linux host. I personally only tested it using WSL + Ubuntu since WSL2 support nested virtualization and I'm using Windows as my main driver.

------------------------------

Current state of the app (will always be updated because since this is an ongoing project to learn elixir):

<img width="1909" height="790" alt="image" src="https://github.com/user-attachments/assets/c760bf21-00c2-4247-9764-7caf53b69e35" />

----------------------------------

https://github.com/user-attachments/assets/63b3412a-749c-470b-a35c-69dd9df38d7a

