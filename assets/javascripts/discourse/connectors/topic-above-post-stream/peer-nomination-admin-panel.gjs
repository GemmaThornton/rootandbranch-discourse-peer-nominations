import Component from "@glimmer/component";
import { action } from "@ember/object";
import { tracked } from "@glimmer/tracking";
import { service } from "@ember/service";
import { on } from "@ember/modifier";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";
import { i18n } from "discourse-i18n";
import PeerDeclineModal from "../../components/peer-decline-modal";

// Reads the peer_nomination block from the topic JSON (added by the
// add_to_serializer(:topic_view, :peer_nomination) hook in plugin.rb).
// Only renders for admins/moderators on topics in a peer-nomination state.
export default class PeerNominationAdminPanel extends Component {
  @service modal;
  @service currentUser;
  @service toasts;
  @service router;

  @tracked busy = false;
  @tracked localState = null; // overrides server state after a click

  static shouldRender(args, { currentUser }) {
    if (!currentUser) return false;
    if (!currentUser.admin && !currentUser.moderator) return false;
    const peer = args.model?.peer_nomination;
    if (!peer || !peer.state) return false;
    return true;
  }

  get topic() {
    return this.args.model;
  }

  get peer() {
    return this.topic?.peer_nomination;
  }

  get currentState() {
    return this.localState || this.peer?.state;
  }

  get isUnderReview() {
    return this.currentState === "under-review";
  }

  get isApproved() {
    return this.currentState === "approved";
  }

  get isDeclined() {
    return this.currentState === "declined";
  }

  get stateLabel() {
    if (this.isApproved) {
      return i18n("peer_nominations.admin_panel.state_approved", {
        date: this.formatDate(this.peer?.resolved_at),
      });
    }
    if (this.isDeclined) {
      return i18n("peer_nominations.admin_panel.state_declined", {
        date: this.formatDate(this.peer?.resolved_at),
      });
    }
    return i18n("peer_nominations.admin_panel.state_under_review");
  }

  formatDate(value) {
    if (!value) return "";
    try {
      return new Date(value).toLocaleDateString();
    } catch (e) {
      return "";
    }
  }

  showToast(messageKey) {
    if (!this.toasts) return;
    this.toasts.success({ data: { message: i18n(messageKey) } });
  }

  @action
  async approve() {
    if (this.busy) return;
    this.busy = true;
    try {
      await ajax(`/peer-nominations/${this.topic.id}/approve`, { type: "POST" });
      this.localState = "approved";
      this.showToast("peer_nominations.admin_panel.approved_toast");
    } catch (err) {
      popupAjaxError(err);
    } finally {
      this.busy = false;
    }
  }

  @action
  openDecline() {
    this.modal.show(PeerDeclineModal, {
      model: {
        topicId: this.topic.id,
        onDeclined: () => {
          this.localState = "declined";
          this.showToast("peer_nominations.admin_panel.declined_toast");
        },
      },
    });
  }

  <template>
    <div class="peer-nomination-admin-panel">
      <h3 class="peer-nomination-admin-panel__title">
        {{i18n "peer_nominations.admin_panel.title"}}
      </h3>
      <p class="peer-nomination-admin-panel__state">{{this.stateLabel}}</p>

      {{#if this.isUnderReview}}
        <div class="peer-nomination-admin-panel__actions">
          <button
            type="button"
            class="btn btn-primary"
            disabled={{this.busy}}
            {{on "click" this.approve}}
          >
            {{#if this.busy}}
              {{i18n "peer_nominations.admin_panel.approve_button_busy"}}
            {{else}}
              {{i18n "peer_nominations.admin_panel.approve_button"}}
            {{/if}}
          </button>
          <button
            type="button"
            class="btn btn-danger"
            disabled={{this.busy}}
            {{on "click" this.openDecline}}
          >
            {{i18n "peer_nominations.admin_panel.decline_button"}}
          </button>
        </div>
      {{/if}}
    </div>
  </template>
}
