Name:       onedesk
Version:    1.1.9
Release:    0
Summary:    RPM package
License:    GPL-3.0
Requires:   gtk3 libxcb1 xdotool libXfixes3 alsa-utils libXtst6 libva2 pam gstreamer-plugins-base gstreamer-plugin-pipewire
Recommends: libayatana-appindicator3-1

# https://docs.fedoraproject.org/en-US/packaging-guidelines/Scriptlets/

%description
The best open-source remote desktop client software, written in Rust.

%prep
# we have no source, so nothing here

%build
# we have no source, so nothing here

%global __python %{__python3}

%install
mkdir -p %{buildroot}/usr/bin/
mkdir -p %{buildroot}/usr/share/onedesk/
mkdir -p %{buildroot}/usr/share/onedesk/files/
mkdir -p %{buildroot}/usr/share/icons/hicolor/256x256/apps/
mkdir -p %{buildroot}/usr/share/icons/hicolor/scalable/apps/
install -m 755 $HBB/target/release/onedesk %{buildroot}/usr/bin/onedesk
install $HBB/libsciter-gtk.so %{buildroot}/usr/share/onedesk/libsciter-gtk.so
install $HBB/res/onedesk.service %{buildroot}/usr/share/onedesk/files/
install $HBB/res/128x128@2x.png %{buildroot}/usr/share/icons/hicolor/256x256/apps/onedesk.png
install $HBB/res/scalable.svg %{buildroot}/usr/share/icons/hicolor/scalable/apps/onedesk.svg
install $HBB/res/onedesk.desktop %{buildroot}/usr/share/onedesk/files/
install $HBB/res/onedesk-link.desktop %{buildroot}/usr/share/onedesk/files/

%files
/usr/bin/onedesk
/usr/share/onedesk/libsciter-gtk.so
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
    rm /usr/share/applications/onedesk.desktop || true
    rm /usr/share/applications/onedesk-link.desktop || true
    update-desktop-database
  ;;
  1)
    # for upgrade
  ;;
esac
