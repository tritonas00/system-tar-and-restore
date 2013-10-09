#!/usr/bin/env python
# -*- coding: utf-8 -*-

from __future__ import division
from __future__ import print_function
from __future__ import unicode_literals
from __future__ import absolute_import

# cross-version compatibility
import sys
if sys.version_info.major < 3:
    import Tkinter as tk
    import ttk
    import tkFileDialog as tkfiledialog
else:
    import tkinter as tk
    from tkinter import ttk
    from tkinter import filedialog as tkfiledialog

import os


class Example(ttk.Frame):
    def __init__(self, parent):
        # We can't use super() because in Python 2 the Tkinter objects
        # derive from old-style classes.
        ttk.Frame.__init__(self, parent, borderwidth=3)
        self.parent = parent

        # Create the Tkinter Variables
        self.destination_folder = tk.StringVar()
        self.archiver = tk.StringVar()
        self.compression = tk.StringVar()
        self.exclude_home = tk.BooleanVar()
        self.no_hidden = tk.BooleanVar()
        self.user_options = tk.StringVar()
        self.command = tk.StringVar()

        # Set default values to the Tkinter Variables
        self.destination_folder.set(os.path.expandvars("$HOME"))
        self.archiver.set("tar")
        self.compression.set("gzip")
        self.exclude_home.set(False)
        self.no_hidden.set(False)
        #self.user_options.set("")
        self.construct_command()

        self.create_UI()

    def create_UI(self):
        # set theming
        self.style = ttk.Style()
        self.style.theme_use("default")
        self.pack(fill="both", expand=1)

        # set grid configuration
        self.columnconfigure(1, weight=0)
        self.columnconfigure(2, weight=1)
        self.columnconfigure(3, weight=0)

        # add widgets
        self.add_choose_folder(row=1, text="Destination folder:", variable=self.destination_folder, command=self.construct_command)
        self.add_combobox(row=2, text="Archiver:", variable=self.archiver, values=["tar", "bsdtar"], command=self.construct_command)
        self.add_combobox(row=3, text="Compression:", variable=self.compression, values=["gzip", "xz"], command=self.construct_command)
        self.add_entry(row=4, text="Additional archiver options:", variable=self.user_options, command=self.construct_command)
        self.add_checkbutton(row=5, text="Exclude /home but keep hidden files and folders", variable=self.exclude_home, command=self.construct_command)
        self.add_checkbutton(row=6, text="Don't keep /home 's hidden files and folders.", variable=self.no_hidden, command=self.construct_command)
        self.add_entry(row=7, text="Executable command:", variable=self.command, command=self.construct_command)

    def add_checkbutton(self, row, text, variable, command=None):
        check_button = ttk.Checkbutton(self, text=text, variable=variable, command=command)
        check_button.grid(row=row, column=1, columnspan=2, sticky="nsew")

    def add_choose_folder(self, row, text, variable, command=None):
        def callback():
            variable.set(tkfiledialog.askdirectory())
            if command:
                command()

        # create the widgets
        label = ttk.Label(self, text=text)
        entry = ttk.Entry(self, textvariable=variable, state="readonly")
        button = ttk.Button(self, text="...", command=callback, width=2)
        # place the widgets
        label.grid(row=row, column=1, sticky="nse")
        entry.grid(row=row, column=2, sticky="nsew")
        button.grid(row=row, column=3)

    def add_combobox(self, row, text, variable, values, command=None):
        # create the widgets
        label = ttk.Label(self, text=text)
        #box = ttk.Combobox(self, textvariable=variable, state="readonly", values=values, postcommand=command)
        box = ttk.Combobox(self, textvariable=variable, state="readonly", values=values)
        box.bind("<<ComboboxSelected>>", command)
        # place the widgets
        label.grid(row=row, column=1, sticky="nse")
        box.grid(row=row, column=2, sticky="nsew")

    def add_entry(self, row, text, variable, command=None):
        # create the widgets
        label = ttk.Label(self, text=text)
        entry = ttk.Entry(self, textvariable=variable) #command=command)
        entry.bind("<Key>", self.construct_command)
        # place the widgets
        label.grid(row=row, column=1, sticky="nse")
        entry.grid(row=row, column=2, sticky="nsew")

    def construct_command(self, *args):
        arguments = [
            self.destination_folder.get(),
            "--archiver " + self.archiver.get(),
            "--compression " + self.compression.get()
        ]
        self.command.set("backup.sh " + " ".join(arguments))



from collections import OrderedDict

HOME_FOLDER_MODES = OrderedDict(
    [("Include /home/*", ""),
     ("Only include /home/* 's hidden files and folders.", "--exclude-home"),
     ("Exclude /home/*", "--exclude-home --no-hidden")])

class Example(ttk.Frame):
    def __init__(self, parent):
        # We can't use super() because in Python 2 the Tkinter objects
        # derive from old-style classes.
        ttk.Frame.__init__(self, parent, borderwidth=3)
        self.parent = parent

        # Create the Tkinter Variables
        self.destination_folder = tk.StringVar()
        self.archiver = tk.StringVar()
        self.compression = tk.StringVar()
        self.home_folder = tk.StringVar()
        #self.exclude_home = tk.BooleanVar()
        #self.no_hidden = tk.BooleanVar()
        self.user_options = tk.StringVar()
        self.command = tk.StringVar()

        # Trace the Tkinter Variables!
        # http://stackoverflow.com/a/6549535/592289
        self.destination_folder.trace("w", self.construct_command)
        self.archiver.trace("w", self.construct_command)
        self.compression.trace("w", self.construct_command)
        self.home_folder.trace("w", self.construct_command)
        #self.exclude_home.trace("w", self.construct_command)
        #self.no_hidden.trace("w", self.construct_command)
        self.user_options.trace("w", self.construct_command)

        # Set default values to the Tkinter Variables
        self.destination_folder.set(os.path.expandvars("$HOME"))
        self.archiver.set("tar")
        self.compression.set("gzip")
        #self.exclude_home.set(False)
        #self.no_hidden.set(False)
        self.user_options.set("")
        self.construct_command()

        self.create_UI()

    def create_UI(self):
        # set theming
        self.style = ttk.Style()
        self.style.theme_use("default")
        self.pack(fill="both", expand=1)

        # set grid configuration
        self.columnconfigure(1, weight=0)
        self.columnconfigure(2, weight=1)
        self.columnconfigure(3, weight=0)

        # add widgets
        self.add_choose_folder(row=1, text="Destination folder:", variable=self.destination_folder)
        self.add_combobox(row=2, text="Archiver:", variable=self.archiver, values=["tar", "bsdtar"])
        self.add_combobox(row=3, text="Compression:", variable=self.compression, values=["gzip", "xz"])
        self.add_entry(row=4, text="Additional archiver options:", variable=self.user_options)
        #self.add_checkbutton(row=5, text="Exclude /home but keep hidden files and folders", variable=self.exclude_home, command=self.construct_command)
        #self.add_checkbutton(row=6, text="Don't keep /home 's hidden files and folders.", variable=self.no_hidden, command=self.construct_command)
        self.add_radiobuttons(row=5, variable=self.home_folder, modes=HOME_FOLDER_MODES)
        self.add_entry(row=8, text="Executable command:", variable=self.command)

    def add_radiobuttons(self, row, modes, variable):
        for i, (label, value) in enumerate(modes.items()):
            radio_button = ttk.Radiobutton(self, text=label, value=value, variable=variable)
            radio_button.grid(row=row + i, column=2, columnspan=1, sticky="nsew")


    def add_checkbutton(self, row, text, variable):
        check_button = ttk.Checkbutton(self, text=text, variable=variable)
        check_button.grid(row=row, column=1, columnspan=2, sticky="nsew")

    def add_choose_folder(self, row, text, variable):
        # create the widgets
        label = ttk.Label(self, text=text)
        entry = ttk.Entry(self, textvariable=variable, state="readonly")
        button = ttk.Button(self, text="...", width=2, command=lambda: variable.set(tkfiledialog.askdirectory()))
        # place the widgets
        label.grid(row=row, column=1, sticky="nse")
        entry.grid(row=row, column=2, sticky="nsew")
        button.grid(row=row, column=3)

    def add_combobox(self, row, text, variable, values):
        # create the widgets
        label = ttk.Label(self, text=text)
        box = ttk.Combobox(self, textvariable=variable, state="readonly", values=values)
        #box.bind("<<ComboboxSelected>>", command)
        # place the widgets
        label.grid(row=row, column=1, sticky="nse")
        box.grid(row=row, column=2, sticky="nsew")

    def add_entry(self, row, text, variable):
        # create the widgets
        label = ttk.Label(self, text=text)
        entry = ttk.Entry(self, textvariable=variable)
        #entry.bind("<Key>", self.construct_command)
        # place the widgets
        label.grid(row=row, column=1, sticky="nse")
        entry.grid(row=row, column=2, sticky="nsew")

    def construct_command(self, *args):
        arguments = [
            self.destination_folder.get(),
            "--archiver " + self.archiver.get(),
            "--compression " + self.compression.get(),
            self.home_folder.get(),
            self.user_options.get(),
        ]
        self.command.set("backup.sh " + " ".join(arguments))



def main():
    root = tk.Tk()
    root.title("backup.sh GUI")
    app = Example(root)
    app.update()
    root.minsize(root.winfo_width(), root.winfo_height())
    root.mainloop()

def main():
    root = tk.Tk()
    root.title("backup.sh GUI")
    app = Example(root)
    app.update()
    root.minsize(root.winfo_width(), root.winfo_height())

    termf = ttk.Frame(root, height=200, width=200)
    termf.pack(fill="both", expand=1)
    wid = termf.winfo_id()
    os.system('xterm -into %d -geometry 40x24 -sb &' % wid)

    root.mainloop()

main()

if __name__ == '__main__':
    main()


        #self.create_menu()
    #def create_menu(self):
        ## Necessay in order to remove a dashed line at the menu.
        #self.option_add("*tearOff", False)

        ## Create the menubar
        #menubar = tk.Menu(self.parent)

        ## Create the file menu and add its contents
        #file_menu = tk.Menu(menubar)
        #file_menu.add_command(label="Quit", command=sys.exit)

        ## add the menus to the menubar
        #menubar.add_cascade(label="File", menu=file_menu)

        ## Not really sure why this is necessary...
        #self.parent.config(menu=menubar)

