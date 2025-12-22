// SPDX-FileCopyrightText: 2022  Emmanuele Bassi
// SPDX-License-Identifier: GPL-3.0-or-later

mod application;
mod audio;
mod config;
mod cover_picture;
mod drag_overlay;
mod i18n;
mod marquee;
mod playback_control;
mod playlist_view;
mod queue_row;
mod search;
mod song_cover;
mod song_details;
mod sort;
mod utils;
mod volume_control;
mod waveform_view;
mod window;

use std::env;

use config::{APPLICATION_ID, GETTEXT_PACKAGE, LOCALEDIR, PKGDATADIR, PROFILE};
use gettextrs::{bind_textdomain_codeset, bindtextdomain, setlocale, textdomain, LocaleCategory};
use gtk::{gio, glib, prelude::*};
use log::{debug, error, LevelFilter};

use self::application::Application;

fn main() -> glib::ExitCode {
    let mut builder = pretty_env_logger::formatted_builder();
    if APPLICATION_ID.ends_with("Devel") {
        builder.filter(Some("amberol"), LevelFilter::Debug);
    } else {
        builder.filter(Some("amberol"), LevelFilter::Info);
    }
    builder.init();

    // Set up gettext translations
    debug!("Setting up locale data");
    setlocale(LocaleCategory::LcAll, "");

    bindtextdomain(GETTEXT_PACKAGE, LOCALEDIR).expect("Unable to bind the text domain");
    bind_textdomain_codeset(GETTEXT_PACKAGE, "UTF-8")
        .expect("Unable to set the text domain encoding");
    textdomain(GETTEXT_PACKAGE).expect("Unable to switch to the text domain");

    #[cfg(any(target_os = "linux", target_os = "freebsd"))]
    {
        debug!("Setting up pulseaudio environment");
        let app_id = APPLICATION_ID.trim_end_matches(".Devel");
        env::set_var("PULSE_PROP_application.icon_name", app_id);
        env::set_var("PULSE_PROP_application.metadata().name", "Amberol");
        env::set_var("PULSE_PROP_media.role", "music");
    }

    debug!("Loading resources");
    let resources = match env::var("MESON_DEVENV") {
        Ok(_) => {
            match env::current_exe() {
                Ok(path) => {
                    let mut resource_path = path;
                    resource_path.pop();
                    resource_path.push("amberol.gresource");
                    gio::Resource::load(&resource_path)
                        .expect("Unable to find amberol.gresource in devenv")
                }
                Err(err) => {
                    error!("Unable to find the current path: {}", err);
                    return glib::ExitCode::FAILURE;
                }
            }
        }
        Err(_) => {
            // Production mode: try multiple locations
            let resource_paths = [
                // macOS app bundle: look for ../share/amberol relative to executable
                env::current_exe()
                    .ok()
                    .map(|p| {
                        let mut path = p;
                        path.pop(); // Remove executable name
                        path.pop(); // Remove MacOS
                        path.push("share");
                        path.push("amberol");
                        path.push("amberol.gresource");
                        path
                    }),
                // AMBEROL_PKGDATADIR environment variable (for app bundle launcher)
                env::var("AMBEROL_PKGDATADIR")
                    .ok()
                    .map(|p| std::path::PathBuf::from(p).join("amberol.gresource")),
                // Standard install location
                Some(std::path::PathBuf::from(PKGDATADIR).join("amberol.gresource")),
            ];

            let mut loaded_resource = None;
            for path_opt in resource_paths.iter() {
                if let Some(path) = path_opt {
                    debug!("Trying to load gresource from: {:?}", path);
                    if let Ok(res) = gio::Resource::load(path) {
                        loaded_resource = Some(res);
                        break;
                    }
                }
            }

            loaded_resource.expect("Unable to find amberol.gresource in any expected location")
        }
    };
    gio::resources_register(&resources);

    debug!("Setting up application (profile: {})", &PROFILE);
    glib::set_application_name("Amberol");
    glib::set_program_name(Some("amberol"));

    gst::init().expect("Failed to initialize gstreamer");

    let ctx = glib::MainContext::default();
    let _guard = ctx.acquire().unwrap();

    Application::new().run()
}
