Name:       onedesk
Version:    1.4.4
Release:    0
Summary:    RPM package
License:    GPL-3.0
URL:        https://rustdesk.com
Vendor:     onedesk <info@onedesk.co.kr>
Requires:   gtk3 libxcb1 xdotool libXfixes3 alsa-utils libXtst6 libva2 pam gstreamer-plugins-base gstreamer-plugin-pipewire
Recommends: libayatana-appindicator3-1
Provides:   libdesktop_drop_plugin.so()(64bit), libdesktop_multi_window_plugin.so()(64bit), libfile_selector_linux_plugin.so()(64bit), libflutter_custom_cursor_plugin.so()(64bit), libflutter_linux_gtk.so()(64bit), libscreen_retriever_plugin.so()(64bit), libtray_manager_plugin.so()(64bit), liburl_launcher_linux_plugin.so()(64bit), libwindow_manager_plugin.so()(64bit), libwindow_size_plugin.so()(64bit), libtexture_rgba_renderer_plugin.so()(64bit)

# https://docs.fedoraproject.org/en-US/packaging-guidelines/Scriptlets/

%description
The best open-source remote desktop client software, written in Rust.

%prep
# we have no source, so nothing here

%build
# we have no source, so nothing here

# %global __python %{__python3}

%install

mkdir -p "%{buildroot}/usr/share/onedesk" && cp -r ${HBB}/flutter/build/linux/x64/release/bundle/* -t "%{buildroot}/usr/share/onedesk"
mkdir -p "%{buildroot}/usr/bin"
install -Dm 644 $HBB/res/onedesk.service -t "%{buildroot}/usr/share/onedesk/files"
install -Dm 644 $HBB/res/onedesk.desktop -t "%{buildroot}/usr/share/onedesk/files"
install -Dm 644 $HBB/res/onedesk-link.desktop -t "%{buildroot}/usr/share/onedesk/files"
install -Dm 644 $HBB/res/128x128@2x.png "%{buildroot}/usr/share/icons/hicolor/256x256/apps/onedesk.png"
install -Dm 644 $HBB/res/scalable.svg "%{buildroot}/usr/share/icons/hicolor/scalable/apps/onedesk.svg"

%files
/usr/share/onedesk/*
/usr/share/onedesk/files/onedesk.service
/usr/share/icons/hicolor/256x256/apps/onedesk.png
/usr/share/icons/hicolor/scalable/apps/onedesk.svg
/usr/share/onedesk/files/onedesk.desktop
/usr/share/onedesk/files/onedesk-link.desktop

%changelog
# let's skip this for now

%pre
# can do something for centos7
case "$1" in
  1)
    # for install
  ;;
  2)
    # for upgrade
    systemctl stop onedesk || true
  ;;
esac

%post
cp /usr/share/onedesk/files/onedesk.service /etc/systemd/system/onedesk.service
cp /usr/share/onedesk/files/onedesk.desktop /usr/share/applications/
cp /usr/share/onedesk/files/onedesk-link.desktop /usr/share/applications/
ln -sf /usr/share/onedesk/onedesk /usr/bin/onedesk
systemctl daemon-reload
systemctl enable onedesk
systemctl start onedesk
update-desktop-database

%preun
case "$1" in
  0)
    # for uninstall
    systemctl stop onedesk || true
    systemctl disable onedesk || true
    rm /etc/systemd/system/onedesk.service || true
  ;;
  1)
    # for upgrade
  ;;
esac

%postun
case "$1" in
  0)
    # for uninstall
    rm /usr/bin/onedesk || true
    rmdir /usr/lib/onedesk || true
    rmdir /usr/local/onedesk || true
    rmdir /usr/share/onedesk || true
    rm /usr/share/applications/onedesk.desktop || true
    rm /usr/share/applications/onedesk-link.desktop || true
    update-desktop-database
  ;;
  1)
    # for upgrade
    rmdir /usr/lib/onedesk || true
    rmdir /usr/local/onedesk || true
  ;;
esac
