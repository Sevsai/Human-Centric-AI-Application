#!/bin/bash

if [ -f .env ]; then
    # Automatically export all variables from .env
    set -a
    source .env
    set +a
else
    echo "Error: .env file not found. Please ensure it exists in the current directory."
    exit 1
fi

# Run the Python script embedded in this bash script.
python3 <<EOF
import os
import tkinter as tk
from tkinter import ttk, messagebox, font, filedialog
import time
import json
import openai
from threading import Thread, Event
import logging
from openai import OpenAI
# Setup logging for error tracking
logging.basicConfig(filename='app.log', level=logging.ERROR, format='%(asctime)s:%(levelname)s:%(message)s')

# Initialize OpenAI client using the correct method
openai_api_key = os.getenv("OPENAI_API_KEY")
if not openai_api_key:
    messagebox.showerror("API Key Error", "OPENAI_API_KEY not found in .env file.")
    exit(1)


client = openai.OpenAI(api_key=openai_api_key)

model_settings = {
    "model": "gpt-4o",  # Ensure this is the correct model you intend to use
    "temperature": 0.7,
    "top_p": 1,
    "max_tokens": 16380,
    "frequency_penalty": 0.0,
    "presence_penalty": 0.0
}

stop_event = Event()

def load_instructions():
    instructions_filepath = "instructions.json"
    if not os.path.exists(instructions_filepath):
        messagebox.showerror("File Error", f"Instructions file '{instructions_filepath}' not found.")
        return None

    with open(instructions_filepath, "r", encoding="utf-8") as file:
        try:
            instructions = json.load(file)
        except json.JSONDecodeError as e:
            messagebox.showerror("File Error", f"Error reading '{instructions_filepath}': {e}")
            return None

    return instructions

instructions_data = load_instructions()
if not instructions_data:
    raise Exception("Failed to load instructions. Exiting...")

root = tk.Tk()
root.title("OpenAI Chat Enhanced")
root.geometry("1200x800")
root.minsize(800, 600)
root.configure(bg="#2c3e50")

themes = {
    "Dark": {
        "bg": "#2c3e50",
        "fg": "#ecf0f1",
        "input_bg": "#34495e",
        "output_bg": "#34495e"
    },
    "Light": {
        "bg": "#f0f0f0",
        "fg": "#2c3e50",
        "input_bg": "#ffffff",
        "output_bg": "#ffffff"
    },
    "Blue": {
        "bg": "#1e3d59",
        "fg": "#ecf0f1",
        "input_bg": "#3a506b",
        "output_bg": "#3a506b"
    }
}

current_theme = "Dark"

def apply_theme(theme_name):
    theme = themes.get(theme_name, themes["Dark"])
    root.configure(bg=theme["bg"])
    left_frame.configure(bg=theme["bg"])
    right_frame.configure(bg=theme["bg"])
    settings_frame.configure(bg=theme["bg"])
    for widget in left_frame.winfo_children():
        if isinstance(widget, (ttk.Label, ttk.Button, ttk.Checkbutton, tk.Label, tk.Entry)):
            widget.configure(background=theme["bg"], foreground=theme["fg"])
    for frame in notebook.winfo_children():
        frame.configure(bg=theme["bg"])
        for widget in frame.winfo_children():
            if isinstance(widget, (ttk.Label, tk.Text)):
                widget.configure(background=theme["bg"], foreground=theme["fg"])
    for menubutton in actions_menus:
        menubutton.configure(background=theme["bg"], foreground=theme["fg"])
    root.update_idletasks()

menu_bar = tk.Menu(root)
root.config(menu=menu_bar)

theme_menu = tk.Menu(menu_bar, tearoff=0)
menu_bar.add_cascade(label="Theme", menu=theme_menu)
for theme_name in themes.keys():
    theme_menu.add_command(label=theme_name, command=lambda tn=theme_name: apply_theme(tn))

def open_button_manager():
    manager = tk.Toplevel(root)
    manager.title("Manage Actions")
    manager.geometry("500x500")
    manager.configure(bg=themes[current_theme]["bg"])

    tk.Label(manager, text="Add New Action:", bg=themes[current_theme]["bg"], fg=themes[current_theme]["fg"],
             font=('Segoe UI', 12, 'bold')).pack(pady=10)

    frame = tk.Frame(manager, bg=themes[current_theme]["bg"])
    frame.pack(pady=5, padx=10)

    # Action Name
    tk.Label(frame, text="Action Name:", bg=themes[current_theme]["bg"], fg=themes[current_theme]["fg"]).grid(row=0, column=0, padx=5, pady=5, sticky='e')
    action_name_entry = ttk.Entry(frame, width=30)
    action_name_entry.grid(row=0, column=1, padx=5, pady=5)

    # Action Type
    tk.Label(frame, text="Action Type:", bg=themes[current_theme]["bg"], fg=themes[current_theme]["fg"]).grid(row=1, column=0, padx=5, pady=5, sticky='e')
    action_type = ttk.Combobox(frame, values=["Predefined Action", "Custom Prompt"], state="readonly")
    action_type.grid(row=1, column=1, padx=5, pady=5)
    action_type.current(0)

    # Predefined Actions
    predefined_actions = list(instructions_data.get("button_instructions", {}).keys())
    tk.Label(frame, text="Select Predefined Action:", bg=themes[current_theme]["bg"], fg=themes[current_theme]["fg"]).grid(row=2, column=0, padx=5, pady=5, sticky='e')
    action_selector = ttk.Combobox(frame, values=predefined_actions, state="readonly")
    action_selector.grid(row=2, column=1, padx=5, pady=5)
    if predefined_actions:
        action_selector.current(0)

    # Custom Prompt
    custom_prompt_label = tk.Label(frame, text="Custom Prompt:", bg=themes[current_theme]["bg"], fg=themes[current_theme]["fg"])
    custom_prompt = tk.Text(frame, height=4, width=30, state='disabled')
    custom_prompt_label.grid(row=3, column=0, padx=5, pady=5, sticky='ne')
    custom_prompt.grid(row=3, column=1, padx=5, pady=5)

    def toggle_custom_prompt(event):
        if action_type.get() == "Custom Prompt":
            custom_prompt.configure(state='normal')
        else:
            custom_prompt.delete("1.0", tk.END)
            custom_prompt.configure(state='disabled')

    action_type.bind("<<ComboboxSelected>>", toggle_custom_prompt)

    def add_action():
        action_name = action_name_entry.get().strip()
        if not action_name:
            messagebox.showwarning("Input Error", "Action name cannot be empty.")
            return

        if action_type.get() == "Predefined Action":
            selected_action = action_selector.get()
            if selected_action not in instructions_data.get("button_instructions", {}):
                messagebox.showerror("Selection Error", "Selected predefined action does not exist.")
                return
            # Add to button_functions
            button_functions[action_name] = lambda i=0, act=selected_action: generate_response(i, act)
        else:
            prompt = custom_prompt.get("1.0", tk.END).strip()
            if not prompt:
                messagebox.showwarning("Input Error", "Custom prompt cannot be empty.")
                return
            button_functions[action_name] = lambda i=0, prm=prompt: generate_response(i, prm)

        custom_buttons[action_name] = button_functions[action_name]
        refresh_actions_menu()
        actions_menus_label.config(text=f"Actions ({len(button_functions)} total)")
        buttons_list.insert(tk.END, action_name)
        messagebox.showinfo("Success", f"Action '{action_name}' added successfully.")
        manager.destroy()

    ttk.Button(manager, text="Add Action", command=add_action).pack(pady=10)

    tk.Label(manager, text="Existing Actions:", bg=themes[current_theme]["bg"], fg=themes[current_theme]["fg"],
             font=('Segoe UI', 12, 'bold')).pack(pady=10)

    buttons_list = tk.Listbox(manager, bg=themes[current_theme]["input_bg"], fg=themes[current_theme]["fg"])
    buttons_list.pack(pady=5, fill=tk.BOTH, expand=True)

    for btn in button_functions.keys():
        buttons_list.insert(tk.END, btn)

    def remove_action():
        selected = buttons_list.curselection()
        if not selected:
            messagebox.showwarning("Selection Error", "No action selected.")
            return
        action_name = buttons_list.get(selected[0])
        if action_name in button_functions:
            del button_functions[action_name]
            del custom_buttons[action_name]
            refresh_actions_menu()
            actions_menus_label.config(text=f"Actions ({len(button_functions)} total)")
            buttons_list.delete(selected[0])
            messagebox.showinfo("Success", f"Action '{action_name}' removed successfully.")

    ttk.Button(manager, text="Remove Selected Action", command=remove_action).pack(pady=5)

custom_buttons = {}

# Initialize button_functions with predefined actions
button_functions = {}
for key, value in instructions_data.get("button_instructions", {}).items():
    button_functions[key] = lambda i=0, act=key: generate_response(i, act)

def refresh_actions_menu():
    for menubutton in actions_menus:
        menu = menubutton.menu
        menu.delete(0, 'end')
        for button_text, command in button_functions.items():
            menu.add_command(label=button_text, command=lambda cmd=command: cmd())

left_frame = tk.Frame(root, bg=themes[current_theme]["bg"])
left_frame.grid(row=0, column=0, sticky="nsew", padx=10, pady=10)

right_frame = tk.Frame(root, bg=themes[current_theme]["bg"])
right_frame.grid(row=0, column=1, sticky="nsew", padx=10, pady=10)

root.grid_rowconfigure(0, weight=1)
root.grid_columnconfigure(0, weight=3)
root.grid_columnconfigure(1, weight=1)

system_instruction_var = tk.StringVar(value=instructions_data.get("system_instruction", ""))

label_font = font.Font(family="Segoe UI", size=12, weight="bold")
input_font = ("Segoe UI", 11)
output_font = ("Segoe UI", 11)

def get_input_text(page_index):
    return input_entries[page_index].get("1.0", tk.END).strip()

def append_to_data_file(prompt, response):
    timestamp = time.strftime("%Y-%m-%d %H:%M:%S")
    try:
        with open("data.txt", "a", encoding="utf-8") as file:
            file.write(f"\n--- {timestamp} ---\n--- Prompt ---\n{prompt}\n--- Response ---\n{response}\n")
    except Exception as e:
        logging.error(f"Failed to append to data file: {e}")

def handle_generation_error(e):
    stop_progress()
    messagebox.showerror("Error", f"An error occurred during AI interaction: {e}")
    logging.error(f"AI Generation Error: {e}")

def start_progress():
    progress_bar.start()
    progress_bar.config(mode="indeterminate")

def stop_progress():
    progress_bar.stop()
    progress_bar.config(mode="determinate", value=0)

def generate_response(page_index, prompt_key=""):
    def async_generate():
        input_text = get_input_text(page_index)
        if not input_text:
            messagebox.showwarning("Input Error", "Please enter some text.")
            return

        output_texts[page_index].insert(tk.END, f"\n--- Response Start ---\n")
        start_progress()
        stop_event.clear()

        response_count = int(response_count_var.get()) if multi_response_mode.get() else 1

        try:
            for _ in range(response_count):
                if stop_event.is_set():
                    break
                if prompt_key in instructions_data.get("button_instructions", {}):
                    prompt = instructions_data["button_instructions"][prompt_key]
                else:
                    prompt = prompt_key if prompt_key else input_text

                completion = client.chat.completions.create(
                    model=model_settings["model"],
                    messages=[
                        {"role": "system", "content": system_instruction_var.get()},
                        {"role": "user", "content": prompt + input_text if prompt else input_text}
                    ],
                    temperature=model_settings["temperature"],
                    top_p=model_settings["top_p"],
                    max_tokens=model_settings["max_tokens"],
                    frequency_penalty=model_settings["frequency_penalty"],
                    presence_penalty=model_settings["presence_penalty"]
                )

                response = completion.choices[0].message.content.strip()
                output_texts[page_index].insert(tk.END, response + "\n")
                output_texts[page_index].see(tk.END)
                append_to_data_file(prompt + input_text if prompt else input_text, response)

            stop_progress()
            output_texts[page_index].insert(tk.END, f"--- Response End ---\n")
        except Exception as e:
            handle_generation_error(e)

    Thread(target=async_generate, daemon=True).start()

def save_session(page_index):
    session_data = {
        "input": get_input_text(page_index),
        "output": output_texts[page_index].get("1.0", tk.END).strip(),
        "timestamp": time.strftime("%Y-%m-%d %H:%M:%S")
    }
    try:
        with open(f"session_{page_index + 1}.json", "w", encoding="utf-8") as file:
            json.dump(session_data, file, ensure_ascii=False, indent=4)
        messagebox.showinfo("Session Saved", f"Session {page_index + 1} saved successfully.")
    except Exception as e:
        logging.error(f"Failed to save session: {e}")
        messagebox.showerror("File Error", f"Unable to save session: {e}")

def load_session(page_index):
    filepath = filedialog.askopenfilename(
        defaultextension=".json",
        filetypes=[("JSON Files", "*.json"), ("All Files", "*.*")]
    )
    if filepath:
        try:
            with open(filepath, "r", encoding="utf-8") as file:
                session_data = json.load(file)
            input_entries[page_index].delete("1.0", tk.END)
            input_entries[page_index].insert(tk.END, session_data['input'])
            output_texts[page_index].insert(tk.END, session_data['output'] + "\n")
        except Exception as e:
            logging.error(f"Failed to load session: {e}")
            messagebox.showerror("File Error", f"Unable to load session: {e}")

notebook = ttk.Notebook(left_frame)
notebook.grid(row=0, column=0, sticky="nsew")

multi_response_mode = tk.IntVar()
multi_response_button = ttk.Checkbutton(right_frame, text="Multi Response Mode", variable=multi_response_mode, onvalue=1, offvalue=0, command=lambda: toggle_multi_response_mode())
multi_response_button.grid(row=0, column=0, sticky="w", pady=15)

response_count_var = tk.StringVar(value="1")
response_count_label = ttk.Label(right_frame, text="Number of responses:", background=themes[current_theme]["bg"], foreground=themes[current_theme]["fg"])
response_count_dropdown = ttk.Combobox(right_frame, values=[1, 2, 3, 4, 5, 6, 7, 8, 9, 10], state="readonly", width=5, textvariable=response_count_var)
response_count_dropdown.current(0)

def toggle_multi_response_mode():
    if multi_response_mode.get() == 1:
        response_count_label.grid(row=1, column=0, sticky="w", pady=5)
        response_count_dropdown.grid(row=1, column=1, pady=5)
    else:
        response_count_label.grid_forget()
        response_count_dropdown.grid_forget()

num_pages = 15
input_entries = []
output_texts = []
actions_menus = []

for i in range(num_pages):
    page = tk.Frame(notebook, bg=themes[current_theme]["bg"])
    notebook.add(page, text=f"Page {i + 1}")

    input_frame = tk.Frame(page, bg=themes[current_theme]["bg"])
    input_frame.grid(row=0, column=0, sticky="nsew", padx=10, pady=5)
    input_frame.grid_rowconfigure(1, weight=1)
    input_frame.grid_columnconfigure(0, weight=1)

    input_label = ttk.Label(input_frame, text="Input:", font=label_font, background=themes[current_theme]["bg"], foreground=themes[current_theme]["fg"])
    input_label.grid(row=0, column=0, sticky="w")

    input_entry = tk.Text(input_frame, wrap=tk.WORD, font=input_font, bg=themes[current_theme]["input_bg"], fg=themes[current_theme]["fg"], insertbackground=themes[current_theme]["fg"], height=10)
    input_entry.grid(row=1, column=0, sticky="nsew")

    input_scroll = ttk.Scrollbar(input_frame, command=input_entry.yview)
    input_entry['yscrollcommand'] = input_scroll.set
    input_scroll.grid(row=1, column=1, sticky="ns")

    actions_frame = tk.Frame(page, bg=themes[current_theme]["bg"])
    actions_frame.grid(row=1, column=0, sticky="ew", padx=10, pady=5)

    actions_menu = tk.Menubutton(actions_frame, text="Actions", relief=tk.RAISED, bg=themes[current_theme]["bg"], fg=themes[current_theme]["fg"])
    actions_menu.menu = tk.Menu(actions_menu, tearoff=0)
    actions_menu["menu"] = actions_menu.menu
    actions_menu.grid(row=0, column=0, padx=5, pady=5)
    actions_menus.append(actions_menu)

    # Refresh the actions menu with the current buttons
    refresh_actions_menu()

    generate_button = ttk.Button(actions_frame, text="Generate", command=lambda i=i: generate_response(i), width=15)
    generate_button.grid(row=0, column=1, padx=5)

    stop_button = ttk.Button(actions_frame, text="Stop", command=lambda: stop_generation(), width=15)
    stop_button.grid(row=0, column=2, padx=5)

    # Add a button to manage actions
    manage_actions_button = ttk.Button(actions_frame, text="Manage Actions", command=open_button_manager, width=15)
    manage_actions_button.grid(row=0, column=3, padx=5)

    output_frame = tk.Frame(page, bg=themes[current_theme]["bg"])
    output_frame.grid(row=2, column=0, sticky="nsew", padx=10, pady=5)
    output_frame.grid_rowconfigure(1, weight=1)
    output_frame.grid_columnconfigure(0, weight=1)

    output_label = ttk.Label(output_frame, text="Output:", font=label_font, background=themes[current_theme]["bg"], foreground=themes[current_theme]["fg"])
    output_label.grid(row=0, column=0, sticky="w")

    output_text = tk.Text(output_frame, wrap=tk.WORD, font=output_font, bg=themes[current_theme]["output_bg"], fg=themes[current_theme]["fg"], insertbackground=themes[current_theme]["fg"], height=15)
    output_text.grid(row=1, column=0, sticky="nsew")

    output_scroll = ttk.Scrollbar(output_frame, command=output_text.yview)
    output_text['yscrollcommand'] = output_scroll.set
    output_scroll.grid(row=1, column=1, sticky="ns")

    input_entries.append(input_entry)
    output_texts.append(output_text)

progress_bar = ttk.Progressbar(root, orient="horizontal", mode="determinate")
progress_bar.grid(row=1, column=0, columnspan=2, sticky="ew", padx=5, pady=5)

def stop_generation():
    stop_event.set()
    stop_progress()
    messagebox.showinfo("Stopped", "AI generation has been stopped.")

def load_goals():
    if os.path.exists("Updates.txt"):
        with open("Updates.txt", "r", encoding="utf-8") as file:
            return file.read().strip().splitlines()
    return []

def save_goals(goals):
    with open("Updates.txt", "w", encoding="utf-8") as file:
        for goal in goals:
            file.write(f"{goal}\n")

def update_goals():
    current_goals = load_goals()
    new_goal_prompt = "Based on the user needs and AI's interpretation, suggest a new goal:"
    response = generate_response_with_prompt(new_goal_prompt)
    if response:
        current_goals.append(response)
        save_goals(current_goals)
        messagebox.showinfo("Goals Updated", "New goals have been added. You can edit them in Updates.txt.")

def generate_response_with_prompt(prompt):
    try:
        completion = client.chat.completions.create(
            model=model_settings["model"],
            messages=[
                {"role": "system", "content": system_instruction_var.get()},
                {"role": "user", "content": prompt}
            ],
            temperature=model_settings["temperature"],
            top_p=model_settings["top_p"],
            max_tokens=model_settings["max_tokens"],
            frequency_penalty=model_settings["frequency_penalty"],
            presence_penalty=model_settings["presence_penalty"]
        )
        return completion.choices[0].message.content.strip()
    except Exception as e:
        handle_generation_error(e)
        return None

update_goals_button = ttk.Button(right_frame, text="Update Goals", command=update_goals)
update_goals_button.grid(row=2, column=0, pady=5)

# System instructions editor
ttk.Label(right_frame, text="System Instructions:", background=themes[current_theme]["bg"], foreground=themes[current_theme]["fg"]).grid(row=3, column=0, pady=10, sticky="w")
system_instructions_text = tk.Text(right_frame, wrap=tk.WORD, font=input_font, height=10, width=30, bg=themes[current_theme]["input_bg"], fg=themes[current_theme]["fg"], insertbackground=themes[current_theme]["fg"])
system_instructions_text.grid(row=4, column=0, pady=5, padx=5, sticky="nsew")
system_instructions_text.insert(tk.END, instructions_data.get("system_instruction", ""))

def save_system_instructions():
    instructions_data["system_instruction"] = system_instructions_text.get("1.0", tk.END).strip()
    with open("instructions.json", "w", encoding="utf-8") as file:
        json.dump(instructions_data, file, ensure_ascii=False, indent=4)
    messagebox.showinfo("Save Successful", "System instructions have been updated.")
    
save_instructions_button = ttk.Button(right_frame, text="Save Instructions", command=save_system_instructions)
save_instructions_button.grid(row=5, column=0, pady=5)

def load_from_file(page_index):
    filepath = filedialog.askopenfilename(
        defaultextension=".txt",
        filetypes=[("Text Files", "*.txt"), ("All Files", "*.*")]
    )
    if filepath:
        try:
            with open(filepath, "r", encoding="utf-8") as file:
                input_text = file.read()
            input_entries[page_index].delete("1.0", tk.END)
            input_entries[page_index].insert(tk.END, input_text)
        except Exception as e:
            logging.error(f"Failed to load file: {e}")
            messagebox.showerror("File Error", f"Unable to load file: {e}")

def save_to_file(page_index):
    filepath = filedialog.asksaveasfilename(
        defaultextension=".txt",
        filetypes=[("Text Files", "*.txt"), ("All Files", "*.*")]
    )
    if filepath:
        try:
            with open(filepath, "w", encoding="utf-8") as file:
                file.write(output_texts[page_index].get("1.0", tk.END))
            messagebox.showinfo("File Saved", "Output successfully saved to file.")
        except Exception as e:
            logging.error(f"Failed to save file: {e}")
            messagebox.showerror("File Error", f"Unable to save file: {e}")

def clear_output(page_index):
    output_texts[page_index].delete("1.0", tk.END)

settings_frame = tk.Frame(left_frame, bg=themes[current_theme]["bg"])
settings_frame.grid(row=3, column=0, sticky="ew", pady=10)

ttk.Label(settings_frame, text="Temperature:", background=themes[current_theme]["bg"], foreground=themes[current_theme]["fg"]).grid(row=0, column=0, padx=5, pady=2, sticky='e')
temperature_entry = ttk.Entry(settings_frame)
temperature_entry.grid(row=0, column=1, padx=5, pady=2)
temperature_entry.insert(0, str(model_settings["temperature"]))

ttk.Label(settings_frame, text="Top P:", background=themes[current_theme]["bg"], foreground=themes[current_theme]["fg"]).grid(row=1, column=0, padx=5, pady=2, sticky='e')
top_p_entry = ttk.Entry(settings_frame)
top_p_entry.grid(row=1, column=1, padx=5, pady=2)
top_p_entry.insert(0, str(model_settings["top_p"]))

ttk.Label(settings_frame, text="Max Tokens:", background=themes[current_theme]["bg"], foreground=themes[current_theme]["fg"]).grid(row=2, column=0, padx=5, pady=2, sticky='e')
max_tokens_entry = ttk.Entry(settings_frame)
max_tokens_entry.grid(row=2, column=1, padx=5, pady=2)
max_tokens_entry.insert(0, str(model_settings["max_tokens"]))

ttk.Label(settings_frame, text="Frequency Penalty:", background=themes[current_theme]["bg"], foreground=themes[current_theme]["fg"]).grid(row=3, column=0, padx=5, pady=2, sticky='e')
frequency_penalty_entry = ttk.Entry(settings_frame)
frequency_penalty_entry.grid(row=3, column=1, padx=5, pady=2)
frequency_penalty_entry.insert(0, str(model_settings["frequency_penalty"]))

ttk.Label(settings_frame, text="Presence Penalty:", background=themes[current_theme]["bg"], foreground=themes[current_theme]["fg"]).grid(row=4, column=0, padx=5, pady=2, sticky='e')
presence_penalty_entry = ttk.Entry(settings_frame)
presence_penalty_entry.grid(row=4, column=1, padx=5, pady=2)
presence_penalty_entry.insert(0, str(model_settings["presence_penalty"]))

ttk.Label(settings_frame, text="Select Model:", background=themes[current_theme]["bg"], foreground=themes[current_theme]["fg"]).grid(row=5, column=0, padx=5, pady=5, sticky='e')
model_selector = ttk.Combobox(settings_frame, values=["gpt-4o-mini", "gpt-4", "gpt-3.5-turbo", "chatgpt-4o-latest", "gpt-4-1106-preview", "gpt-4o", "gpt-o1"], state="readonly")
model_selector.grid(row=5, column=1, padx=5, pady=5)
model_selector.set(model_settings["model"])

# Button to apply settings
def apply_settings():
    try:
        model_settings["temperature"] = float(temperature_entry.get())
        model_settings["top_p"] = float(top_p_entry.get())
        model_settings["max_tokens"] = int(max_tokens_entry.get())
        model_settings["frequency_penalty"] = float(frequency_penalty_entry.get())
        model_settings["presence_penalty"] = float(presence_penalty_entry.get())
        model_settings["model"] = model_selector.get()
        messagebox.showinfo("Settings Updated", "Model settings have been updated successfully.")
    except ValueError:
        messagebox.showerror("Input Error", "Please enter valid numeric values for the settings.")

apply_settings_button = ttk.Button(settings_frame, text="Apply Settings", command=apply_settings)
apply_settings_button.grid(row=6, column=0, columnspan=2, pady=10)



def generate_photo(prompt):
    def async_generate_photo():
        if not prompt.strip():
            messagebox.showwarning("Input Error", "Please enter a prompt for photo generation.")
            return
        try:
            # Assuming the OpenAI API has an images endpoint; replace with the correct method if available
            client = OpenAI()
            response = client.images.generate(
                prompt=prompt,
                n=1,
                size="512x512"
            )
            print(response.data[0].url)
            image_url = response['data'][0]['url']
            image_data = requests.get(image_url).content
            image = Image.open(io.BytesIO(image_data))
            image = image.resize((300, 300), Image.ANTIALIAS)
            photo = ImageTk.PhotoImage(image)
            photo_window = tk.Toplevel(root)
            photo_window.title("Generated Photo")
            photo_label = tk.Label(photo_window, image=photo)
            photo_label.image = photo  # Keep a reference
            photo_label.pack()
        except Exception as e:
            handle_generation_error(e)

    # Start the image generation in a separate thread
    Thread(target=async_generate_photo).start()

# Adding Photo Generation Button
photo_frame = tk.Frame(right_frame, bg=themes[current_theme]["bg"])
photo_frame.grid(row=11, column=0, pady=10, sticky="ew")

photo_prompt_var = tk.StringVar()
photo_prompt_entry = ttk.Entry(photo_frame, textvariable=photo_prompt_var, width=30)
photo_prompt_entry.pack(side="left", padx=5)

generate_photo_button = ttk.Button(photo_frame, text="Generate Photo", command=lambda: generate_photo(photo_prompt_var.get()))
generate_photo_button.pack(side="left", padx=5)

# **End of Photo Generation Feature**



root.mainloop()
EOF
