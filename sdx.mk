include $(TOPDIR)/owrt-qti-bsp/qtibsp.mk
include $(TOPDIR)/owrt-qti-bsp-prop/qtibspprop.mk
include $(TOPDIR)/owrt-qti-core/qticore.mk
include $(TOPDIR)/owrt-qti-core-prop/qticoreprop.mk
include $(TOPDIR)/owrt-qti-ss-mgr/qtissmgr.mk
include $(TOPDIR)/owrt-qti-ss-mgr-prop/qtissmgrprop.mk
include $(TOPDIR)/owrt-qti-location/qtilocation.mk
include $(TOPDIR)/owrt-qti-location-prop/qtilocationprop.mk
include $(TOPDIR)/owrt-qti-data/qtidata.mk
include $(TOPDIR)/owrt-qti-data-prop/qtidataprop.mk
include $(TOPDIR)/owrt-qti-ril-prop/qtirilprop.mk

# include mk files available only in internal builds
ifneq ($(EXTERNAL_BUILD),1)
	include $(TOPDIR)/owrt-qti-location-internal/qtilocationinternal.mk
endif

OPENWRT_STANDARD:=luci openssl-util diag

UTILS:=file luci-app-samba rng-tools profilerd tcpdump ip-bridge conntrack conntrackd ethtool pciutils

COREBSP_UTILS:=pm-utils

ifeq ($(EXTERNAL_BUILD),1)
QTIDATAPROP += xmllib_prebuilt libnetmgr_rmnet_ext_prebuilt
endif

define Profile/SDX65_Olympic
	NAME:=Qualcomm Technologies, Inc SDX65 Olympic Profile
	PACKAGES:=$(OPENWRT_STANDARD) \
		$(COREBSP_UTILS) $(UTILS) \
		$(QTIBSP) $(QTIBSPPROP) $(QTICORE) $(QTICOREPROP) $(QTISSMGR) $(QTISSMGRPROP) \
		$(QTILOCATION) $(QTILOCATIONPROP) $(QTILOCATIONINTERNAL) \
		$(QTIDATA) $(QTIDATAPROP) $(QTIRILPROP) \
		-lacpd libtirpc -swconfig
endef

define Profile/SDX65_Olympic/Description
	Sdx65 Olympic package set configuration.
	Enables sdx65 Olympic source packages
endef

$(eval $(call Profile,SDX65_Olympic))

define Profile/SDX75_Pinnacles
	NAME:=Qualcomm Technologies, Inc SDX75 Pinnacles Profile
	PACKAGES:=$(OPENWRT_STANDARD) \
		$(COREBSP_UTILS) $(UTILS) \
		$(QTIBSP) $(QTIBSPPROP) $(QTICORE) $(QTICOREPROP) $(QTISSMGR) $(QTISSMGRPROP) \
		ipa_fws -linux-msm-5.4_dt -lacpd libtirpc -swconfig
endef

define Profile/SDX75_Pinnacles/Description
	Sdx75 Pinnacles package set configuration.
	Enables sdx75 Pinnacles source packages
endef

$(eval $(call Profile,SDX75_Pinnacles))

define Profile/SDX35_Kuno
	NAME:=Qualcomm Technologies, Inc SDX35 Kuno Profile
	PACKAGES:=$(OPENWRT_STANDARD) \
		$(COREBSP_UTILS) $(UTILS) \
		$(QTIBSP) $(QTIBSPPROP) $(QTICORE) $(QTICOREPROP) $(QTISSMGR) $(QTISSMGRPROP) \
		$(QTIDATA) $(QTIDATAPROP) \
		$(QTILOCATION) $(QTILOCATIONPROP) $(QTILOCATIONINTERNAL) \
		ipa_fws -linux-msm-5.4_dt -lacpd libtirpc -swconfig
endef

define Profile/SDX35_Kuno/Description
	Sdx35 Kuno package set configuration.
	Enables sdx35 Kuno source packages
endef

$(eval $(call Profile,SDX35_Kuno))
