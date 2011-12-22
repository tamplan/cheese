/*
 * Copyright © 2010 Yuvaraj Pandian T <yuvipanda@yuvi.in>
 * Copyright © 2010 daniel g. siegel <dgsiegel@gnome.org>
 * Copyright © 2008 Filippo Argiolas <filippo.argiolas@gmail.com>
 *
 * Licensed under the GNU General Public License Version 2
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */

using Gtk;
using Gdk;
using GtkClutter;
using Clutter;
using Config;
using Eog;
using Gst;
using Gee;
using CanberraGtk;

const int FULLSCREEN_TIMEOUT_INTERVAL = 5 * 1000;
const int EFFECTS_PER_PAGE            = 9;
const string SENDTO_EXEC = "nautilus-sendto";

public class Cheese.MainWindow : Gtk.Window
{
  private MediaMode current_mode;

  private Gtk.Builder    gtk_builder;
  private Clutter.Script clutter_builder;

  private GLib.Settings settings;

  private Gtk.Widget       thumbnails;
  private GtkClutter.Embed viewport_widget;
  private Gtk.Grid          main_vbox;
  private Eog.ThumbNav     thumb_nav;
  private Cheese.ThumbView thumb_view;
  private Gtk.Alignment    thumbnails_right;
  private Gtk.Alignment    thumbnails_bottom;
  private Gtk.MenuBar      menubar;
  private Gtk.Box          leave_fullscreen_button_container;
  private Gtk.ToggleButton photo_toggle_button;
  private Gtk.ToggleButton video_toggle_button;
  private Gtk.ToggleButton burst_toggle_button;
  private Gtk.Button       take_action_button;
  private Gtk.Label        take_action_button_label;
  private Gtk.Image        take_action_button_image;
  private Gtk.ToggleButton effects_toggle_button;
  private Gtk.Button       leave_fullscreen_button;
  private Gtk.Box          buttons_area;
  private Gtk.Menu         thumbnail_popup;

  private Clutter.Stage     viewport;
  private Clutter.Box       viewport_layout;
  private Clutter.Texture   video_preview;
  private Clutter.BinLayout viewport_layout_manager;
  private Clutter.Text      countdown_layer;
  private Clutter.Rectangle background_layer;
  private Clutter.Text      error_layer;

  private Clutter.Box           current_effects_grid;
  private int                current_effects_page = 0;
  private ArrayList<Clutter.Box> effects_grids;

  private Gtk.Action       take_photo_action;
  private Gtk.Action       take_video_action;
  private Gtk.Action       take_burst_action;
  private Gtk.Action       photo_mode_action;
  private Gtk.Action       video_mode_action;
  private Gtk.Action       burst_mode_action;
  private Gtk.ToggleAction effects_toggle_action;
  private Gtk.ToggleAction wide_mode_action;
  private Gtk.ToggleAction fullscreen_action;
  private Gtk.Action       countdown_action;
  private Gtk.Action       effects_page_prev_action;
  private Gtk.Action       effects_page_next_action;
  private Gtk.Action       share_action;
  private Gtk.ActionGroup  main_actions;

  private bool is_fullscreen;
  private bool is_wide_mode;
  private bool is_recording;       /* Video Recording Flag */
  private bool is_bursting;
  private bool is_effects_selector_active;
  private bool is_camera_actions_sensitive;
  private bool action_cancelled;
  private bool is_command_line_startup;

  private Gtk.Button[] buttons;

  private Cheese.Camera   camera;
  private Cheese.FileUtil fileutil;
  private Cheese.Flash    flash;

  private Cheese.EffectsManager    effects_manager;
  private Cheese.PreferencesDialog preferences_dialog;

  private Cheese.Effect selected_effect;

  private Cheese.ShareableMedia shareable_media;

  /**
   * Destroy the main window, and shutdown the application, when quitting.
   *
   * @param action the action that emitted the signal
   */
  [CCode (instance_pos = -1)]
  public void on_quit (Gtk.Action action)
  {
    destroy ();
  }

  /**
   * Show the preferences dialog when requested, creating it as necessary.
   *
   * @param action the action that emitted the signal
   */
  [CCode (instance_pos = -1)]
  public void on_preferences_dialog (Gtk.Action action)
  {
    if (preferences_dialog == null)
      preferences_dialog = new Cheese.PreferencesDialog (camera, settings);
    preferences_dialog.set_current_mode (current_mode);
    preferences_dialog.show ();
  }

  /**
   * Popup a context menu when right-clicking on a thumbnail.
   *
   * @param iconview the thumbnail view that emitted the signal
   * @param event the event
   * @return false, to allow further processing of the event
   */
  public bool on_thumbnail_mouse_button_press (Gtk.Widget      iconview,
                                               Gdk.EventButton event)
  {
    Gtk.TreePath path;
    path = thumb_view.get_path_at_pos ((int) event.x, (int) event.y);

    if (path == null)
      return false;

    if (!thumb_view.path_is_selected (path))
    {
      thumb_view.unselect_all ();
      thumb_view.select_path (path);
      thumb_view.set_cursor (path, null, false);
    }

    if (event.type == Gdk.EventType.BUTTON_PRESS)
    {
      if (event.button == 3)
      {
	thumbnail_popup.popup (null, thumb_view, null, event.button, event.time);

	// Check whether nautilus-sendto is installed or not. In case it is, set
	// the "Share" action to sensitive, if it is not, set it to insensitive.
	bool nautilus_sendto_installed = Environment.find_program_in_path(SENDTO_EXEC) != null;
	share_action.set_sensitive (nautilus_sendto_installed);
      }
    }
    else
    if (event.type == Gdk.EventType.2BUTTON_PRESS)
    {
      on_file_open (null);
    }

    return false;
  }

  /**
   * Open an image associated with a thumbnail in the default application.
   *
   * @param action the action that emitted the signal, or null
   */
  [CCode (instance_pos = -1)]
  public void on_file_open (Gtk.Action ? action)
  {
    string filename, uri;

    Gdk.Screen screen;
    filename = thumb_view.get_selected_image ();

    if (filename == null)
      return;                     /* Nothing selected. */

    try
    {
      uri    = GLib.Filename.to_uri (filename);
      screen = this.get_screen ();
      Gtk.show_uri (screen, uri, Gtk.get_current_event_time ());
    }
    catch (Error err)
    {
      MessageDialog error_dialog = new MessageDialog (this,
                                                      Gtk.DialogFlags.MODAL |
                                                      Gtk.DialogFlags.DESTROY_WITH_PARENT,
                                                      Gtk.MessageType.ERROR,
                                                      Gtk.ButtonsType.OK,
                                                      _("Could not open %s"),
                                                      filename);

      error_dialog.run ();
      error_dialog.destroy ();
    }
  }

  /**
   * Delete the requested image in the thumbview from storage.
   *
   * A confirmation dialog is shown to the user before deleting the file.
   *
   * @param action the action that emitted the signal
   */
  [CCode (instance_pos = -1)]
  public void on_file_delete (Gtk.Action action)
  {
    File file;
    int response;
    MessageDialog confirmation_dialog;

    GLib.List<GLib.File> files = thumb_view.get_selected_images_list ();

    for (int i = 0; i < files.length (); i++)
    {
      file = files<GLib.File>.nth (i).data;
      if (file == null)
        return;

      confirmation_dialog = new MessageDialog.with_markup (this,
                                                           Gtk.DialogFlags.MODAL | Gtk.DialogFlags.DESTROY_WITH_PARENT,
                                                           Gtk.MessageType.WARNING,
                                                           Gtk.ButtonsType.NONE,
                                                           _("Are you sure you want to permanently delete the file \"%s\"?"),
                                                           file.get_basename ());
      confirmation_dialog.add_button (Gtk.Stock.CANCEL, Gtk.ResponseType.CANCEL);
      confirmation_dialog.add_button (Gtk.Stock.DELETE, Gtk.ResponseType.ACCEPT);
      confirmation_dialog.format_secondary_text ("%s", _("If you delete an item, it will be permanently lost"));
      response = confirmation_dialog.run ();
      confirmation_dialog.destroy ();
      if (response == Gtk.ResponseType.ACCEPT)
      {
        try
        {
          file.delete (null);
        }
        catch (Error err)
        {
          MessageDialog error_dialog = new MessageDialog (this,
                                                          Gtk.DialogFlags.MODAL |
                                                          Gtk.DialogFlags.DESTROY_WITH_PARENT,
                                                          Gtk.MessageType.ERROR,
                                                          Gtk.ButtonsType.OK,
                                                          _("Could not delete %s"),
                                                          file.get_path ());

          error_dialog.run ();
          error_dialog.destroy ();
        }
      }
    }
  }

  /**
   * Move the requested image in the thumbview to the trash.
   *
   * A confirmation dialog is shown to the user before moving the file.
   *
   * @param action the action that emitted the signal
   */
  [CCode (instance_pos = -1)]
  public void on_file_move_to_trash (Gtk.Action action)
  {
    File file;

    GLib.List<GLib.File> files = thumb_view.get_selected_images_list ();

    for (int i = 0; i < files.length (); i++)
    {
      file = files<GLib.File>.nth (i).data;
      if (file == null)
        return;

      try
      {
        file.trash (null);
      }
      catch (Error err)
      {
        MessageDialog error_dialog = new MessageDialog (this,
                                                        Gtk.DialogFlags.MODAL |
                                                        Gtk.DialogFlags.DESTROY_WITH_PARENT,
                                                        Gtk.MessageType.ERROR,
                                                        Gtk.ButtonsType.OK,
                                                        _("Could not move %s to trash"),
                                                        file.get_path ());

        error_dialog.run ();
        error_dialog.destroy ();
      }
    }
  }

  /**
   * Move all images in the thumbview to the trash.
   *
   * No confirmation dialog is shown to the user before moving the files!
   *
   * @param action the action that emitted the signal
   */
  [CCode (instance_pos = -1)]
  public void on_file_move_to_trash_all (Gtk.Action action)
  {
    try {
      File           file_to_trash;
      FileInfo       file_info;
      File           directory  = File.new_for_path (fileutil.get_photo_path ());
      FileEnumerator enumerator = directory.enumerate_children (FILE_ATTRIBUTE_STANDARD_NAME, 0, null);

      while ((file_info = enumerator.next_file (null)) != null)
      {
        file_to_trash = File.new_for_path (fileutil.get_photo_path () + GLib.Path.DIR_SEPARATOR_S + file_info.get_name ());
        file_to_trash.trash (null);
      }

      directory  = File.new_for_path (fileutil.get_video_path ());
      enumerator = directory.enumerate_children (FILE_ATTRIBUTE_STANDARD_NAME, 0, null);

      while ((file_info = enumerator.next_file (null)) != null)
      {
        file_to_trash = File.new_for_path (fileutil.get_photo_path () + GLib.Path.DIR_SEPARATOR_S + file_info.get_name ());
        file_to_trash.trash (null);
      }
    } catch (Error e)
    {
      warning ("Error: %s\n", e.message);
      return;
    }
  }

  /**
   * Share the selected file(s) in the thumbview.
   *
   * A dialog is shown to the user, where the technology for sharing the
   * image or video can be selected.
   *
   * @param action the action that emitted the signal
   */
  [CCode (instance_pos = -1)]
  public void on_share_files (Gtk.Action action)
  {
    shareable_media.share_files (thumb_view.get_selected_images_list ());
  }

  /**
   * Save the selected file in the thumbview to an alternate storage location.
   *
   * A file chooser dialog is shown to the user, asking where the file should
   * be saved and the filename.
   *
   * @param action the action that emitted the signal.
   */
  [CCode (instance_pos = -1)]
  public void on_file_save_as (Gtk.Action action)
  {
    string            filename, basename;
    FileChooserDialog save_as_dialog;
    int               response;

    filename = thumb_view.get_selected_image ();
    if (filename == null)
      return;                    /* Nothing selected. */

    save_as_dialog = new FileChooserDialog (_("Save File"),
                                            this,
                                            Gtk.FileChooserAction.SAVE,
                                            Gtk.Stock.CANCEL, Gtk.ResponseType.CANCEL,
                                            Gtk.Stock.SAVE, Gtk.ResponseType.ACCEPT,
                                            null);

    save_as_dialog.do_overwrite_confirmation = true;
    basename                                 = GLib.Filename.display_basename (filename);
    save_as_dialog.set_current_name (basename);
    save_as_dialog.set_current_folder (GLib.Environment.get_home_dir ());

    response = save_as_dialog.run ();

    save_as_dialog.hide ();
    if (response == Gtk.ResponseType.ACCEPT)
    {
      string target_filename;
      target_filename = save_as_dialog.get_filename ();

      File src  = File.new_for_path (filename);
      File dest = File.new_for_path (target_filename);

      try
      {
        src.copy (dest, FileCopyFlags.OVERWRITE, null, null);
      }
      catch (Error err)
      {
        MessageDialog error_dialog = new MessageDialog (this,
                                                        Gtk.DialogFlags.MODAL |
                                                        Gtk.DialogFlags.DESTROY_WITH_PARENT,
                                                        Gtk.MessageType.ERROR,
                                                        Gtk.ButtonsType.OK,
                                                        _("Could not save %s"),
                                                        target_filename);

        error_dialog.run ();
        error_dialog.destroy ();
      }
    }
    save_as_dialog.destroy ();
  }

  /**
   * Show the Cheese help contents.
   *
   * @param action the action that emitted the signal
   */
  [CCode (instance_pos = -1)]
  public void on_help_contents (Gtk.Action action)
  {
    Gdk.Screen screen;
    screen = this.get_screen ();
    try {
      Gtk.show_uri (screen, "help:cheese", Gtk.get_current_event_time ());
    } catch (Error err)
    {
      warning ("Error: %s\n", err.message);
    }
  }

  /**
   * Show the about dialog.
   *
   * @param action the action that emitted the signal
   */
  [CCode (instance_pos = -1)]
  public void on_help_about (Gtk.Action action)
  {
    Gtk.AboutDialog about_dialog;
    about_dialog         = gtk_builder.get_object ("aboutdialog") as Gtk.AboutDialog;
    about_dialog.set_transient_for (this);
    about_dialog.set_modal (true);
    about_dialog.version = Config.PACKAGE_VERSION;
    about_dialog.run ();
    about_dialog.hide ();
  }

  /**
   * Toggle wide mode and save the preference to GSettings.
   *
   * @param action the action that emitted the signal
   */
  [CCode (instance_pos = -1)]
  public void on_layout_wide_mode (ToggleAction action)
  {
    if (!is_command_line_startup)
    {
     /* Don't save to settings when using -w mode from command-line, so
      * command-line options change the mode for one run only. */
      settings.set_boolean ("wide-mode", action.active);
    }
    set_wide_mode (action.active);
  }

  /**
   * Toggle fullscreen mode and save the preference to GSettings.
   *
   * @param action the action that emitted the signal
   */
  [CCode (instance_pos = -1)]
  public void on_layout_fullscreen (ToggleAction action)
  {
    if (!is_command_line_startup)
    {
     /* Don't save to settings when using -f mode from command-line, so
      * command-line options change the mode for one run only. */
      settings.set_boolean ("fullscreen", action.active);
    }
    set_fullscreen_mode (action.active);
  }

  /**
   * Change the media capture mode (photo, video or burst).
   *
   * @param action the action that emitted the signal
   */
  [CCode (instance_pos = -1)]
  public void on_mode_change (RadioAction action)
  {
    set_mode ((MediaMode) action.value);
  }

  /**
   * Make the media capture mode actions sensitive.
   */
  private void enable_mode_change ()
  {
    photo_mode_action.sensitive = true;
    video_mode_action.sensitive = true;
    burst_mode_action.sensitive = true;
    effects_toggle_action.sensitive = true;
  }

  /**
   * Make the media capture mode actions insensitive.
   */
  private void disable_mode_change ()
  {
     photo_mode_action.sensitive = false;
     video_mode_action.sensitive = false;
     burst_mode_action.sensitive = false;
     effects_toggle_action.sensitive = false;
  }

  /**
   * Set the capture resolution, based on the current capture mode.
   *
   * @param mode the current capture mode (photo, video or burst)
   */
  private void set_resolution(MediaMode mode)
  {
    if (camera == null)
      return;

    unowned GLib.List<VideoFormat> formats = camera.get_video_formats ();

    if (formats == null)
      return;
    
    unowned Cheese.VideoFormat format;
    int width = 0;
    int height = 0;

    switch (mode)
    {
      case MediaMode.PHOTO:
      case MediaMode.BURST:
        width  = settings.get_int ("photo-x-resolution");
        height = settings.get_int ("photo-y-resolution");
        break;
      case MediaMode.VIDEO:
        width  = settings.get_int ("video-x-resolution");
        height = settings.get_int ("video-y-resolution");
        break;
    }

    for (int i = 0; i < formats.length (); i++)
    {
      format = formats<VideoFormat>.nth (i).data;
      if (width == format.width && height == format.height)
      {
        camera.set_video_format (format);
        break;
      }
    }
  }

  /**
   * Set the current media capture mode, and update the UI sensitivities.
   *
   * @param mode the new capture mode to set
   */
  private void set_mode (MediaMode mode)
  {
    this.current_mode = mode;
    
    set_resolution (current_mode);
    
    if (preferences_dialog != null)
      preferences_dialog.set_current_mode (current_mode);
    
    switch (this.current_mode)
    {
      case MediaMode.PHOTO:
        take_photo_action.sensitive       = true;
        take_video_action.sensitive       = false;
        take_burst_action.sensitive       = false;
        take_action_button.related_action = take_photo_action;
        break;

      case MediaMode.VIDEO:
        take_photo_action.sensitive       = false;
        take_video_action.sensitive       = true;
        take_burst_action.sensitive       = false;
        take_action_button.related_action = take_video_action;
        break;

      case MediaMode.BURST:
        take_photo_action.sensitive       = false;
        take_video_action.sensitive       = false;
        take_burst_action.sensitive       = true;
        take_action_button.related_action = take_burst_action;
        break;
    }
    take_action_button_label.label  = "<b>" + take_action_button.related_action.label + "</b>";
    take_action_button.tooltip_text = take_action_button.related_action.tooltip;
}

  private TimeoutSource fullscreen_timeout;
  /**
   * Clear the fullscreen activity timeout.
   */
  private void clear_fullscreen_timeout ()
  {
    if (fullscreen_timeout != null)
    {
      fullscreen_timeout.destroy ();
      fullscreen_timeout = null;
    }
  }

  /**
   * Set the fullscreen timeout, for hiding the UI if there is no mouse
   * movement.
   */
  private void set_fullscreen_timeout ()
  {
    fullscreen_timeout = new TimeoutSource (FULLSCREEN_TIMEOUT_INTERVAL);
    fullscreen_timeout.attach (null);
    fullscreen_timeout.set_callback (() => {buttons_area.hide ();
                                            clear_fullscreen_timeout ();
                                            return true; });
  }

  /**
   * Show the UI in fullscreen if there is any mouse activity.
   *
   * Start a new timeout at the end of every mouse pointer movement. All
   * timeouts will be cancelled, except one created during the last movement
   * event. Show() is called even if the button is not hidden.
   *
   * @param viewport the widget to check for mouse activity on
   * @param e the (unused) event
   */
  private bool fullscreen_motion_notify_callback (Gtk.Widget viewport, EventMotion e)
  {
    clear_fullscreen_timeout ();
    buttons_area.show ();
    set_fullscreen_timeout ();
    return true;
  }

  /**
   * Enable or disable fullscreen mode to the requested state.
   *
   * @param fullscreen_mode whether to enable or disable fullscreen mode
   */
  private void set_fullscreen_mode (bool fullscreen_mode)
  {
    /* After the first time the window has been shown using this.show_all (),
     * the value of leave_fullscreen_button_container.no_show_all should be set to false
     * So that the next time leave_fullscreen_button_container.show_all () is called, the button is actually shown
     * FIXME: If this code can be made cleaner/clearer, please do */

    is_fullscreen = fullscreen_mode;
    if (fullscreen_mode)
    {
      if (is_wide_mode)
      {
        thumbnails_right.hide ();
      }
      else
      {
        thumbnails_bottom.hide ();
      }
      menubar.hide ();
      leave_fullscreen_button_container.no_show_all = false;
      leave_fullscreen_button_container.show_all ();

      /* Make all buttons look 'flat' */
      foreach (Gtk.Button b in buttons)
      {
        if (b.get_name () != "take_action_button")
          b.relief = Gtk.ReliefStyle.NONE;
      }
      this.fullscreen ();
      viewport_widget.motion_notify_event.connect (fullscreen_motion_notify_callback);
      set_fullscreen_timeout ();
    }
    else
    {
      if (is_wide_mode)
      {
        thumbnails_right.show_all ();
      }
      else
      {
        thumbnails_bottom.show_all ();
      }
      menubar.show_all ();
      leave_fullscreen_button_container.hide ();

      /* Make all buttons look, uhm, Normal */
      foreach (Gtk.Button b in buttons)
      {
        if (b.get_name () != "take_action_button")
          b.relief = Gtk.ReliefStyle.NORMAL;
      }

      /* Stop timer so buttons_area does not get hidden after returning from
       * fullscreen mode */
      clear_fullscreen_timeout ();
      /* Show the buttons area anyway - it might've been hidden in fullscreen mode */
      buttons_area.show ();
      viewport_widget.motion_notify_event.disconnect (fullscreen_motion_notify_callback);
      this.unfullscreen ();
    }
  }

  /**
   * Enable or disable wide mode to the requested state.
   *
   * @param wide_mode whether to enable or disable wide mode
   */
  private void set_wide_mode (bool wide_mode)
  {
    is_wide_mode = wide_mode;

    /* keep the viewport to its current size while rearranging the ui,
     * so that thumbview moves from right to bottom and viceversa
     * while the rest of the window stays unchanged */
    Gtk.Allocation alloc;
    viewport_widget.get_allocation (out alloc);
    viewport_widget.set_size_request (alloc.width, alloc.height);

    if (is_wide_mode)
    {
      thumb_view.set_columns (1);
      thumb_nav.set_vertical (true);
      if (thumbnails_bottom.get_child () != null)
      {
        thumbnails_bottom.remove (thumb_nav);
      }
      thumbnails_right.add (thumb_nav);
      thumbnails_right.show_all ();
      thumbnails_right.resize_children ();
      thumbnails_bottom.hide ();
    }
    else
    {
      thumb_view.set_columns (5000);
      thumb_nav.set_vertical (false);
      if (thumbnails_right.get_child () != null)
      {
        thumbnails_right.remove (thumb_nav);
      }
      thumbnails_bottom.add (thumb_nav);
      thumbnails_bottom.show_all ();
      thumbnails_bottom.resize_children ();
      thumbnails_right.hide ();
    }

    /* handy trick to keep the window to the desired size while not
     * requesting a fixed one. This way the window is resized to its
     * natural size (particularly with the constraints imposed by the
     * viewport, see above) but can still be shrinked down */

    Gtk.Requisition req;
    this.get_preferred_size(out req, out req);
    this.resize (req.width, req.height);
    viewport_widget.set_size_request (-1, -1);
  }

  /**
   * Make sure that the layout manager manages the entire stage.
   *
   * @param actor unused
   * @param box unused
   * @param flags unused
   */
  public void on_stage_resize (Clutter.Actor           actor,
                               Clutter.ActorBox        box,
                               Clutter.AllocationFlags flags)
  {
    this.viewport_layout.set_size (viewport.width, viewport.height);
    this.background_layer.set_size (viewport.width, viewport.height);
  }

  /**
   * Toggle whether the countdown is active.
   *
   * @param action the action that emitted the signal
   */
  [CCode (instance_pos = -1)]
  public void on_countdown_toggle (ToggleAction action)
  {
    settings.set_boolean ("countdown", action.active);
  }

  /**
   * The method to call when the countdown is finished.
   */
  private void finish_countdown_callback ()
  {
    if (action_cancelled == false)
    {
      string file_name = fileutil.get_new_media_filename (this.current_mode);

      if (settings.get_boolean ("flash"))
      {
        this.flash.fire ();
      }
      CanberraGtk.play_for_widget (this.main_vbox, 0,
                                   Canberra.PROP_EVENT_ID, "camera-shutter",
                                   Canberra.PROP_MEDIA_ROLE, "event",
                                   Canberra.PROP_EVENT_DESCRIPTION, _("Shutter sound"),
                                   null);
      this.camera.take_photo (file_name);
    }

    if (current_mode == MediaMode.PHOTO)
    {
      take_photo_action.sensitive = true;
      enable_mode_change ();
    }
  }

  Countdown current_countdown;
  /**
   * Start to take a photo, starting a countdown if it is enabled.
   */
  public void take_photo ()
  {
    if (settings.get_boolean ("countdown"))
    {
      if (current_mode == MediaMode.PHOTO)
      {
        take_photo_action.sensitive = false;
        disable_mode_change ();
      }

      current_countdown = new Countdown (this.countdown_layer);
      current_countdown.start (finish_countdown_callback);
    }
    else
    {
      finish_countdown_callback ();
    }
  }

  private int  burst_count;
  private uint burst_callback_id;

  /**
   * Take a photo during burst mode, and increment the burst count.
   *
   * @return true if there are more photos to be taken in the current burst,
   * false otherwise
   */
  private bool burst_take_photo ()
  {
    if (is_bursting && burst_count < settings.get_int ("burst-repeat"))
    {
      this.take_photo ();
      burst_count++;
      return true;
    }
    else
    {
      toggle_photo_bursting (false);
      return false;
    }
  }

  /**
   * Cancel the current activity if the escape key is pressed.
   *
   * @param event the key event, to check which key was pressed
   * @return false, to allow further processing of the event
   */
  private bool on_key_release (Gdk.EventKey event)
  {
    string key;

    key = Gdk.keyval_name (event.keyval);
    if (strcmp (key, "Escape") == 0)
    {
      if ((current_countdown != null && current_countdown.running) || is_bursting || is_recording)
      {
        action_cancelled = true;
        switch (current_mode)
        {
          case MediaMode.PHOTO:
           current_countdown.stop ();
           finish_countdown_callback ();
           break;
          case MediaMode.BURST:
            toggle_photo_bursting (false);
            break;
          case MediaMode.VIDEO:
            toggle_video_recording (false);
            break;
        }
        action_cancelled = false;
      }
      else
      if (is_effects_selector_active)
      {
        effects_toggle_action.set_active (false);
      }
    }
    return false;
  }

  /**
   * Toggle whether video recording is active.
   *
   * @param is_start whether to start video recording
   */
  public void toggle_video_recording (bool is_start)
  {
    if (is_start)
    {
      camera.start_video_recording (fileutil.get_new_media_filename (this.current_mode));
      take_action_button_label.label = "<b>" + _("Stop _Recording") + "</b>";
      take_action_button.tooltip_text = _("Stop recording");
      take_action_button_image.set_from_stock (Gtk.Stock.MEDIA_STOP, Gtk.IconSize.BUTTON);
      this.is_recording = true;
      this.disable_mode_change ();
    }
    else
    {
      camera.stop_video_recording ();
      take_action_button_label.label = "<b>" + take_action_button.related_action.label + "</b>";
      take_action_button.tooltip_text = take_action_button.related_action.tooltip;
      take_action_button_image.set_from_stock (Gtk.Stock.MEDIA_RECORD, Gtk.IconSize.BUTTON);
      this.is_recording = false;
      this.enable_mode_change ();
    }
  }

  /**
   * Toggle whether photo bursting is active.
   *
   * @param is_start whether to start capturing a photo burst
   */
  public void toggle_photo_bursting (bool is_start)
  {
    if (is_start)
    {
      is_bursting = true;
      this.disable_mode_change ();
      effects_toggle_action.sensitive = false;
      take_action_button_label.label  = "<b>" + _("Stop _Taking Pictures") + "</b>";
      take_action_button.tooltip_text = _("Stop taking pictures");
      burst_take_photo ();

      /* Use the countdown duration if it is greater than the burst delay, plus
       * about 500 ms for taking the photo. */
      var burst_delay = settings.get_int ("burst-delay");
      var countdown_duration = 500 + settings.get_int ("countdown-duration") * 1000;
      if ((burst_delay - countdown_duration) < 1000 && settings.get_boolean ("countdown"))
      {
        burst_callback_id = GLib.Timeout.add (countdown_duration, burst_take_photo);
      }
      else
      {
        burst_callback_id = GLib.Timeout.add (burst_delay, burst_take_photo);
      }
    }
    else
    {
      if (current_countdown != null && current_countdown.running)
        current_countdown.stop ();

      is_bursting = false;
      this.enable_mode_change ();
      take_action_button_label.label  = "<b>" + take_action_button.related_action.label + "</b>";
      take_action_button.tooltip_text = take_action_button.related_action.tooltip;
      burst_count = 0;
      fileutil.reset_burst ();
      GLib.Source.remove (burst_callback_id);
    }
  }

  /**
   * Take a photo or burst of photos, or record a video, based on the current
   * capture mode.
   *
   * @param action the action that emitted the signal
   */
  [CCode (instance_pos = -1)]
  public void on_take_action (Gtk.Action action)
  {
    if (current_mode == MediaMode.PHOTO)
    {
      this.take_photo ();
    }
    else
    if (current_mode == MediaMode.VIDEO)
    {
      toggle_video_recording (!is_recording);
    }
    else
    if (current_mode == MediaMode.BURST)
    {
      toggle_photo_bursting (!is_bursting);
    }
  }

  /**
   * Toggle the display of the effect selector.
   *
   * @param action the action that emitted the signal
   */
  [CCode (instance_pos = -1)]
  public void on_effects_toggle (Gtk.ToggleAction action)
  {
    toggle_effects_selector (action.active);
    take_photo_action.sensitive = !action.active;
    take_video_action.sensitive = !action.active;
    take_burst_action.sensitive = !action.active;
    photo_mode_action.sensitive = !action.active;
    video_mode_action.sensitive = !action.active;
    burst_mode_action.sensitive = !action.active;
  }

  /**
   * Change the selected effect, as a new one was selected.
   *
   * @param source unused
   * @param event unused
   * @return false, to allow further event processing
   */
  public bool on_selected_effect_change (Clutter.Actor source,
                                         Clutter.ButtonEvent event)
  {
    selected_effect = source.get_data ("effect");
    camera.set_effect (selected_effect);
    settings.set_string ("selected-effect", selected_effect.name);
    effects_toggle_action.set_active (false);
    return false;
  }

  /**
   * Navigate back one page of effects.
   *
   * @param action the action that emitted the signal
   */
  [CCode (instance_pos = -1)]
  public void on_prev_effects_page (Gtk.Action action)
  {
    if (current_effects_page != 0)
    {
      activate_effects_page (current_effects_page - 1);
    }
  }

  /**
   * Navigate forward one page of effects.
   *
   * @param action the action that emitted the signal
   */
  [CCode (instance_pos = -1)]
  public void on_next_effects_page (Gtk.Action action)
  {
    if (current_effects_page != (effects_manager.effects.size / EFFECTS_PER_PAGE))
    {
      activate_effects_page (current_effects_page + 1);
    }
  }

  /**
   * Switch to the supplied page of effects.
   *
   * @param number the effects page to switch to
   */
  private void activate_effects_page (int number)
  {
    if (!is_effects_selector_active)
      return;
    current_effects_page = number;
    if (viewport_layout.get_children ().index (current_effects_grid) != -1)
    {
      viewport_layout.remove ((Clutter.Actor) current_effects_grid);
    }
    current_effects_grid = effects_grids[number];
    current_effects_grid.set ("opacity", 0);
    viewport_layout.add ((Clutter.Actor) current_effects_grid);
    current_effects_grid.animate (Clutter.AnimationMode.LINEAR, 1000, "opacity", 255);

    for (int i = 0; i < effects_manager.effects.size; i++)
    {
      int           page_of_effect = i / EFFECTS_PER_PAGE;
      Cheese.Effect effect         = effects_manager.effects[i];
      if (page_of_effect == number)
      {
        if (!effect.is_preview_connected ())
        {
          Clutter.Texture texture = effect.get_data<Clutter.Texture> ("texture");
          camera.connect_effect_texture (effect, texture);
        }
        effect.enable_preview ();
      }
      else
      {
        if (effect.is_preview_connected ())
          effect.disable_preview ();
      }
    }
    setup_effects_page_switch_sensitivity ();
  }

  /**
   * Control the sensitivity of the effects page navigation buttons.
   */
  private void setup_effects_page_switch_sensitivity ()
  {
    effects_page_prev_action.sensitive = (is_effects_selector_active && current_effects_page != 0);
    effects_page_next_action.sensitive =
      (is_effects_selector_active && current_effects_page != effects_manager.effects.size / EFFECTS_PER_PAGE);
  }

  /**
   * Toggle the visibility of the effects selector.
   *
   * @param active whether the selector should be active
   */
  private void toggle_effects_selector (bool active)
  {
    is_effects_selector_active = active;
    if (active)
    {
      video_preview.hide ();

      if (effects_grids.size == 0)
      {
        error_layer.text = _("No effects found");
        error_layer.show ();
      }
      else
      {
        current_effects_grid.show ();
        activate_effects_page (current_effects_page);
      }
    }
    else
    {
      if (effects_grids.size == 0)
      {
        error_layer.hide ();
      }
      else
      {
        current_effects_grid.hide ();
      }
      video_preview.show ();
    }

    camera.toggle_effects_pipeline (active);
    setup_effects_page_switch_sensitivity ();
  }

  /**
   * Create the effects selector.
   */
  private void setup_effects_selector ()
  {
    if (current_effects_grid == null)
    {
      effects_manager = new EffectsManager ();
      effects_manager.load_effects ();

      /* Must initialize effects_grids before returning, as it is dereferenced later, bug 654671. */
      effects_grids = new ArrayList<Clutter.Box> ();

      if (effects_manager.effects.size == 0)
      {
        warning ("gnome-video-effects is not installed.");
        return;
      }

      for (int i = 0; i <= effects_manager.effects.size / EFFECTS_PER_PAGE; i++)
      {
        Clutter.TableLayout table_layout = new TableLayout ();
        Clutter.Box grid = new Clutter.Box (table_layout);
        effects_grids.add (grid);
        table_layout.set_column_spacing (10);
        table_layout.set_row_spacing (10);
      }

      for (int i = 0; i < effects_manager.effects.size; i++)
      {
        Effect            effect  = effects_manager.effects[i];
        Clutter.Texture   texture = new Clutter.Texture ();
        Clutter.BinLayout layout  = new Clutter.BinLayout (Clutter.BinAlignment.CENTER,
                                                           Clutter.BinAlignment.CENTER);
        Clutter.Box       box  = new Clutter.Box (layout);
        Clutter.Text      text = new Clutter.Text ();
        Clutter.Rectangle rect = new Clutter.Rectangle ();

        rect.opacity = 128;
        rect.color   = Clutter.Color.from_string ("black");

        texture.keep_aspect_ratio = true;
        box.pack ((Clutter.Actor) texture, null, null);
        box.reactive = true;
        box.set_data ("effect", effect);
        effect.set_data ("texture", texture);

        box.button_release_event.connect (on_selected_effect_change);

        text.text  = effect.name;
        text.color = Clutter.Color.from_string ("white");

        rect.height = text.height + 5;
        box.pack ((Clutter.Actor) rect,
                  "x-align", Clutter.BinAlignment.FILL,
                  "y-align", Clutter.BinAlignment.END, null);

        box.pack ((Clutter.Actor) text,
                  "x-align", Clutter.BinAlignment.CENTER,
                  "y-align", Clutter.BinAlignment.END, null);

        Clutter.TableLayout table_layout = (Clutter.TableLayout) effects_grids[i / EFFECTS_PER_PAGE].layout_manager;
        table_layout.pack ((Clutter.Actor) box,
                           (i % EFFECTS_PER_PAGE) % 3,
                           (i % EFFECTS_PER_PAGE) / 3);
        table_layout.set_expand (box, false, false);
      }

      setup_effects_page_switch_sensitivity ();
      current_effects_grid = effects_grids[0];
    }
  }

  private Gee.HashMap<string, bool> action_sensitivities;
  /**
   * Toggle the sensitvity of the camera actions.
   *
   * @param active whether the camera actions should be sensitive
   */
  public void toggle_camera_actions_sensitivities (bool active)
  {
    is_camera_actions_sensitive = active;
    if (active)
    {
      foreach (string key in action_sensitivities.keys)
      {
        Gtk.Action action = gtk_builder.get_object (key) as Gtk.Action;
        action.sensitive = action_sensitivities.get (key);
      }
    }
    else
    {
      action_sensitivities = new HashMap<string, bool> (GLib.str_hash);
      GLib.SList<weak GLib.Object> objects = gtk_builder.get_objects ();
      foreach (GLib.Object obj in objects)
      {
        if (obj is Gtk.Action)
        {
          Gtk.Action action = (Gtk.Action)obj;
          action_sensitivities.set (action.name, action.sensitive);
        }
      }

      /* Keep only these actions sensitive. */
      string [] active_actions = { "cheese_action",
                                    "edit_action",
                                    "help_action",
                                    "quit",
                                    "help_contents",
                                    "about",
                                    "open",
                                    "save_as",
                                    "move_to_trash",
                                    "delete",
                                    "move_all_to_trash"};

      /* Gross hack because Vala's `in` operator doesn't really work */
      bool flag;
      foreach (GLib.Object obj in objects)
      {
        flag = false;
        if (obj is Gtk.Action)
        {
          Gtk.Action action = (Gtk.Action)obj;
          foreach (string s in active_actions)
          {
            if (action.name == s)
            {
              flag = true;
            }
          }
          if (!flag)
            ((Gtk.Action)obj).sensitive = false;
        }
      }
    }
  }

  /**
   * Update the UI based on state changes of the camera.
   *
   * @param new_state the new Cheese.Camera state
   */
  private void camera_state_changed (Gst.State new_state)
  {
    if (new_state == Gst.State.PLAYING)
    {
      if (!is_camera_actions_sensitive)
        toggle_camera_actions_sensitivities (true);

      Effect effect = effects_manager.get_effect (settings.get_string ("selected-effect"));
      if (effect != null)
        camera.set_effect (effect);
    }
  }

  /**
   * Set wide mode active when started from the command line (and do not change
   * the GSetting).
   */
  public void set_startup_wide_mode ()
  {
    if (is_wide_mode)
    {
      /* Cheese was already in wide mode, avoid setting it again. */
      return;
    }

    is_command_line_startup = true;
    wide_mode_action.set_active (true);
    is_command_line_startup = false;
  }

  /**
   * Set fullscreen mode active when started from the command line (and do not
   * change the GSetting).
   */
  public void set_startup_fullscreen_mode ()
  {
    is_command_line_startup = true;
    fullscreen_action.set_active (true);
    is_command_line_startup = false;
  }

  /**
   * Load the UI from the GtkBuilder description.
   */
  public void setup_ui ()
  {
    gtk_builder     = new Gtk.Builder ();
    clutter_builder = new Clutter.Script ();
    fileutil        = new FileUtil ();
    flash           = new Flash (this);
    settings        = new GLib.Settings ("org.gnome.Cheese");

    try {
      gtk_builder.add_from_file (GLib.Path.build_filename (Config.PACKAGE_DATADIR, "cheese-actions.ui"));
      gtk_builder.add_from_file (GLib.Path.build_filename (Config.PACKAGE_DATADIR, "cheese-about.ui"));
      gtk_builder.add_from_file (GLib.Path.build_filename (Config.PACKAGE_DATADIR, "cheese-main-window.ui"));
      gtk_builder.connect_signals (this);

      clutter_builder.load_from_file (GLib.Path.build_filename (Config.PACKAGE_DATADIR, "cheese-viewport.json"));
    } catch (Error err)
    {
      error ("Error: %s", err.message);
    }

    main_vbox                         = gtk_builder.get_object ("mainbox_normal") as Gtk.Grid;
    thumbnails                        = gtk_builder.get_object ("thumbnails") as Gtk.Widget;
    viewport_widget                   = gtk_builder.get_object ("viewport") as GtkClutter.Embed;
    viewport                          = viewport_widget.get_stage () as Clutter.Stage;
    thumbnails_right                  = gtk_builder.get_object ("thumbnails_right") as Gtk.Alignment;
    thumbnails_bottom                 = gtk_builder.get_object ("thumbnails_bottom") as Gtk.Alignment;
    menubar                           = gtk_builder.get_object ("main_menubar") as Gtk.MenuBar;
    leave_fullscreen_button_container = gtk_builder.get_object ("leave_fullscreen_button_bin") as Gtk.Box;
    photo_toggle_button               = gtk_builder.get_object ("photo_toggle_button") as Gtk.ToggleButton;
    video_toggle_button               = gtk_builder.get_object ("video_toggle_button") as Gtk.ToggleButton;
    burst_toggle_button               = gtk_builder.get_object ("burst_toggle_button") as Gtk.ToggleButton;
    take_action_button                = gtk_builder.get_object ("take_action_button") as Gtk.Button;
    take_action_button_label          = gtk_builder.get_object ("take_action_button_internal_label") as Gtk.Label;
    take_action_button_image          = gtk_builder.get_object ("take_action_button_internal_image") as Gtk.Image;
    effects_toggle_button             = gtk_builder.get_object ("effects_toggle_button") as Gtk.ToggleButton;
    leave_fullscreen_button           = gtk_builder.get_object ("leave_fullscreen_button") as Gtk.Button;
    buttons_area                      = gtk_builder.get_object ("buttons_area") as Gtk.Box;
    thumbnail_popup                   = gtk_builder.get_object ("thumbnail_popup") as Gtk.Menu;

    main_actions             = gtk_builder.get_object ("main_actions") as Gtk.ActionGroup;
    take_photo_action        = gtk_builder.get_object ("take_photo") as Gtk.Action;
    take_video_action        = gtk_builder.get_object ("take_video") as Gtk.Action;
    take_burst_action        = gtk_builder.get_object ("take_burst") as Gtk.Action;
    photo_mode_action        = gtk_builder.get_object ("photo_mode") as Gtk.Action;
    video_mode_action        = gtk_builder.get_object ("video_mode") as Gtk.Action;
    burst_mode_action        = gtk_builder.get_object ("burst_mode") as Gtk.Action;
    effects_toggle_action    = gtk_builder.get_object ("effects_toggle") as Gtk.ToggleAction;
    countdown_action         = gtk_builder.get_object ("countdown") as Gtk.Action;
    wide_mode_action         = gtk_builder.get_object ("wide_mode") as Gtk.ToggleAction;
    fullscreen_action        = gtk_builder.get_object ("fullscreen") as Gtk.ToggleAction;
    effects_page_next_action = gtk_builder.get_object ("effects_page_next") as Gtk.Action;
    effects_page_prev_action = gtk_builder.get_object ("effects_page_prev") as Gtk.Action;
    share_action             = gtk_builder.get_object ("share") as Gtk.Action;

    shareable_media = new Cheese.ShareableMedia (this);
    main_actions.pre_activate.connect(on_action_pre_activated);

    /* Array contains all 'buttons', for easier manipulation
     * IMPORTANT: IF ANOTHER BUTTON IS ADDED UNDER THE VIEWPORT, ADD IT TO THIS ARRAY */
    buttons = {photo_toggle_button,
               video_toggle_button,
               burst_toggle_button,
               take_action_button,
               effects_toggle_button,
               leave_fullscreen_button};

    video_preview           = clutter_builder.get_object ("video_preview") as Clutter.Texture;
    viewport_layout         = clutter_builder.get_object ("viewport_layout") as Clutter.Box;
    viewport_layout_manager = clutter_builder.get_object ("viewport_layout_manager") as Clutter.BinLayout;
    countdown_layer         = clutter_builder.get_object ("countdown_layer") as Clutter.Text;
    background_layer        = clutter_builder.get_object ("background") as Clutter.Rectangle;
    error_layer             = clutter_builder.get_object ("error_layer") as Clutter.Text;

    video_preview.keep_aspect_ratio = true;
    video_preview.request_mode      = Clutter.RequestMode.HEIGHT_FOR_WIDTH;
    viewport.add_actor (background_layer);
    viewport_layout.set_layout_manager (viewport_layout_manager);

    viewport.add_actor (viewport_layout);

    viewport.allocation_changed.connect (on_stage_resize);

    thumb_view = new Cheese.ThumbView ();
    thumb_nav  = new Eog.ThumbNav (thumb_view, false);

    Gtk.CssProvider css;
    try
    {
      css = new Gtk.CssProvider();
      css.load_from_path (GLib.Path.build_filename (Config.PACKAGE_DATADIR, "cheese.css"));
    }
    catch (Error e)
    {
      stdout.printf ("Error: %s\n", e.message);
    }

    Gtk.StyleContext context;
    context = thumb_view.get_style_context ();
    screen = Gdk.Screen.get_default();
    context.add_provider_for_screen (screen, css, STYLE_PROVIDER_PRIORITY_USER);

    thumb_view.button_press_event.connect (on_thumbnail_mouse_button_press);

    this.add (main_vbox);
    main_vbox.show_all ();

    /* needed for the sizing tricks in set_wide_mode (allocation is 0
     * if the widget is not realized */
    viewport_widget.realize ();

    /* call set_active instead of our set_wide_mode so that the toggle
     * action state is updated */
    wide_mode_action.set_active (settings.get_boolean ("wide-mode"));

    /* apparently set_active doesn't emit toggled nothing has
     * changed, do it manually */
    if (!settings.get_boolean ("wide-mode"))
      wide_mode_action.toggled ();

    set_mode (MediaMode.PHOTO);
    setup_effects_selector ();

    toggle_camera_actions_sensitivities (false);

    this.key_release_event.connect (on_key_release);

    if (settings.get_boolean ("fullscreen"))
      fullscreen_action.active = true;
  }

  /**
   * Decide which actions will be sensitive or insensitive.
   *
   * @param action the action that emitted the signal.
   */
  public void on_action_pre_activated (Gtk.Action action)
  {
     if (strcmp (action.get_name(), "edit_action") == 0)
     {
        if (thumb_view.get_selected_images_list () != null)
        {
           bool nautilus_sendto_installed = Environment.find_program_in_path(SENDTO_EXEC) != null;
           share_action.set_sensitive (nautilus_sendto_installed);
        } else
           share_action.set_sensitive (false);
     }
  }

  /**
   * Setup the camera listed in GSettings.
   *
   * @param uri the uri of the device node to setup, or null
   */
  public void setup_camera (string ? uri)
  {
    string device;
    double value;

    if (uri != null && uri.length > 0)
      device = uri;
    else
      device = settings.get_string ("camera");

    camera = new Camera (video_preview,
                         device,
                         settings.get_int ("photo-x-resolution"),
                         settings.get_int ("photo-y-resolution"));
    try {
      camera.setup (device);
    }
    catch (Error err)
    {
      video_preview.hide ();
      warning ("Error: %s\n", err.message);
      error_layer.text = err.message;
      error_layer.show ();

      toggle_camera_actions_sensitivities (false);
      return;
    }

    value = settings.get_double ("brightness");
    if (value != 0.0)
      camera.set_balance_property ("brightness", value);

    value = settings.get_double ("contrast");
    if (value != 1.0)
      camera.set_balance_property ("contrast", value);

    value = settings.get_double ("hue");
    if (value != 0.0)
      camera.set_balance_property ("hue", value);

    value = settings.get_double ("saturation");
    if (value != 1.0)
      camera.set_balance_property ("saturation", value);

    camera.state_flags_changed.connect (camera_state_changed);
    camera.play ();
  }

  /**
   * Setup the thumbview thumbnail monitors.
   */
  public void start_thumbview_monitors ()
  {
    thumb_view.start_monitoring_video_path (fileutil.get_video_path ());
    thumb_view.start_monitoring_photo_path (fileutil.get_photo_path ());
  }
}
